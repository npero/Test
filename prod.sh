#!/usr/bin/perl

use feature qw(say);
use Term::ReadKey;
use FindBin;

;

$release_tag_regex=qr/(\w+)-(\d)\.(\d+)\.(\d+)\.?(\d*)/;
$VERSION = '$major.$minor.$hotfix';
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

$branch_name = "prod";
$uri="http://192.168.15.173:8080";

$fix_release = 1 if $ARGV[0] eq "FIX";
$roll_release = 1 if $ARGV[0] eq "ROLL";
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
	`git fetch origin staging`;  restore_and_die "Cannot fetch origin/staging, stopped" if $?;
	$diff=`git diff --stat origin/staging staging`; restore_and_die "Please synchronize your staging before any deployment, stopped" if $diff;
}


$_ = `git describe --tags --abbrev=0 --match=prod-*`; 
print "Current staging tag is $_";
if (/$release_tag_regex/) {
	$env_name = $1;
	$major = $2;
	$minor = $3;
   	$hotfix = $4;
} else {
	restore_and_die "Wrong tag description, stopped";
}

$current_version = interpolate $VERSION;
$hotfix_branchname = "hotfix-$current_version";

if($roll_release) {
	$minor ++;
	$hotfix = '0';
	$new_tag = interpolate $TAG;
	$new_version= interpolate $VERSION;
	# We would like a linear staging/prod branch without the feature commits
	`git merge --no-ff staging -m "$new_tag"`; restore_and_die "Cannot merge master into $branch_name, stopped" if $?;
	say "Merge staging into $branch_name, done.";
	say "Minor tag has been incremented and the bug count reset.";
   	say qq/Start deployment of the rolling release "$new_tag"./;
} elsif ($fix_release) {
	$hotfix ++;
	$new_tag = interpolate $TAG;
	$new_version = interpolate $VERSION;

	`git merge --ff-only $hotfix_branchname`; restore_and_die "Cannot merge bugfix into $branch_name, stopped" if $?;
   	say "Merge $hotfix_branchname into $branch_name, done.";

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

say "Publish_$branch_name into Github";
`git push origin $branch_name`; restore_and_die "Cannot push $branch_name to origin, stopped" if $?;
`git push origin $new_tag`; restore_and_die "Cannot push new tag to origin, stopped" if $?;

say "Deployment successful.";

`git branch -D $hotfix_branchname`; restore_and_die "Cannot delete previous bugfix-branch : $bugfix_branchname" if $?;
`git push origin :$hotfix_branchname`; restore_and_die "Cannot delete previous remote bugfix-branch : origin/$bugfix_branchname" if $?;

$new_hotfix_branchname = "hotfix-$new_version";
`git branch $new_hotfix_branchname`;
`git push origin $new_hotfix_branchname`;

`git checkout staging`; die "Cannot checkout staging, stopped" if $?;
if($fix_release){
	`git cherry-pick $new_tag`; restore_and_die "Cannot cherry-pick $new_tag, stopped" if $?;
	`git commit --amend -m "$new_tag"`; restore_and_die "Cannot amend the last commit after cherry-picking" if $?;
	`git push origin staging`; restore_and_die "Cannot push staging to origin, stopped" if $?;
}

`git checkout master`; die "Cannot checkout master, stopped" if $?;

;
# say "Start code analysing with sonar";
# `mvn sonar:sonar  -DartifactVersion=$new_version -Dsonar.dynamicAnalysis=reuseReports -Dsonar.skipDesign=true`;

exit 0;
