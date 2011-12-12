#!/usr/bin/perl

use feature qw(say);
use Term::ReadKey;
use FindBin;
use Getopt::Long;

$major_flag='';
GetOptions ("major"  => \$major_flag);
;

$release_tag_regex=qr/(\w+)-(\d)\.(\d+)\.(\d+)\.?(\d*)/;
$VERSION = '$major.$minor.$release.$bugfix';
$TAG = '$env_name' . '-' . $VERSION;

# Pass a CONSTANT string containing $variable to interpolate dynamically.
sub interpolate {
	eval "qq/$_[0]/";
}

sub restore_and_die {
	`git checkout master`;
	die $_[0];
}

$working_dir = "$FindBin::RealBin/../../";
# chdir($working_dir);

if ($ARGV[0] eq "staging") {
   $branch_name = "staging";
   $uri="http://192.168.13.78:8080";
} elsif ($ARGV[0] eq "prod") {
   $branch_name = "prod";
   $uri="http://192.168.15.173:8080";
} else {
   die "Do you deploy in staging or prod ?";
}

$uri="http://192.168.64.128:8080";

$fix_release = 1 if $ARGV[1] eq "FIX";
$roll_release = 1 if $ARGV[1] eq "ROLL";
die "Is this a FIX or ROLL release, Please tell me!" unless ($fix_release || $roll_release);

ReadMode('noecho');
say "Deploy to $branch_name@$uri. Please enter the server password:";
$password = ReadLine(0);
unless (length $password) {
	die "Missing password, stopped";
}

`git checkout $branch_name`; die "Cannot checkout into $branch_name, stopped" if $?;

say "Check if $branch_name is in sync with Github.";
`git fetch origin`; restore_and_die "Cannot fetch origin/$branch_name, stopped" if $?;
$diff=`git diff --stat origin/$branch_name $branch_name`; restore_and_die "Please synchronize your $branch_name before any deployment, stopped" if $diff;

if ($roll_release) {
    say "Roll release: check if master is in sync with Github.";
	`git fetch origin master`;  restore_and_die "Cannot fetch origin/master, stopped" if $?;
	$diff=`git diff --stat origin/master master`; restore_and_die "Please synchronize your master before any deployment, stopped" if $diff;
}

$_ = `git describe --tags --abbrev=0 --match=staging-*`; 
print "Current tag is $_";
if (/$release_tag_regex/) {
	$env_name = $1;
	$major = $2;
	$minor = $3;
   	$release = $4;
	$bugfix = $5;
} else {
	restore_and_die "Wrong tag description, stopped";
}

$current_version = interpolate $VERSION;

if($roll_release) {
	$release ++;
	$new_tag = interpolate $TAG;
	$new_version= interpolate $VERSION;
	# We would like a linear staging/prod branch without the feature commits
	`git merge --no-ff master -m "$new_tag"`; restore_and_die "Cannot merge master into $branch_name, stopped" if $?;
	say "Merge master into $branch_name, done.";
	say "Sub-version tag has been incremented and the bug count reset.";
   	say qq/Start deployment of the rolling release "$new_tag"./;
} elsif ($fix_release) {
	$bugfix ++;
	$new_tag = interpolate $TAG;
	$new_version = interpolate $VERSION;
	$bugfix_branchname = "bugfix-$new_version";

	`git merge --ff-only $bugfix_branchname`; restore_and_die "Cannot merge bugfix into $branch_name, stopped" if $?;
   	say "Merge $bugfix_branchname into $branch_name, done.";

	say "The bug count has been incremented.";
   	say qq/Start deployment of the fixing release "$new_tag"/;
}

# Build the artifact (will be install whenever sonar is accessible remotely
print
"\t - run all tests,\n\t - build the artifact,\n\t - send it to the remote server to be deployed.\n This takes a while ...\n";
# `mvn clean tomcat:redeploy -DfailIfNoTests=false -DbaseUri=$uri -DartifactVersion=$new_version -Dtomcat.password=$password`;
if ($?) {
	say "Redeploy FAILED!";
	`git reset --hard HEAD^`;
	print "\t$branch_name has been reset to previous state. " unless $?;
	restore_and_die "\tSource won't be tagged, stopped";
}

say "Deploy of $new_version into $branch_name succeeds."; 

say "About to tag the source with $new_tag";
`git tag $new_tag`; restore_and_die "Cannot tag source, stopped" if $?;

# Let's not create bug fix branch automatically for now.
# Whenever there is a bug in staging/prod let's do it manually

# if ($roll_release) { # create a new bug fix branch
#     my $new_bugfix_branchname = "bugfix-$new_version";
#     `git branch $new_bugfix_branchname`;
#     `git push origin $new_bugfix_branchname`;
#     say qq/
#     A new "$new_bugfix_branchname" branch has been created and published.
#     If $branch_name "$new_version" has not been released into production,
#     you can now manually remove the "bugfix-$current_version" branch locally and remotely./;
# }

say "Publish_$branch_name into Github";
`git push origin $branch_name`; restore_and_die "Cannot push $branch_name to origin, stopped" if $?;
`git push origin $new_tag`; restore_and_die "Cannot push new tag to origin, stopped" if $?;

say "Deployment successful.";

`git checkout master`; die "Cannot checkout master, stopped" if $?;

# say "Start code analysing with sonar";
# `mvn sonar:sonar  -DartifactVersion=$new_version -Dsonar.dynamicAnalysis=reuseReports -Dsonar.skipDesign=true`;

exit 0;
