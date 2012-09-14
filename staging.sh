#!/usr/bin/perl

use feature qw(say);
use Term::ReadKey;
use FindBin;
use Getopt::Long;

;

$release_tag_regex=qr/(\w+)-(\d)\.(\d+)\.(\d+)\.?(\d*)/;
$VERSION = '$major.$minor.$release.$bugfix';
$NEW_VERSION = '$new_major.$new_minor.$release.$bugfix';
$TAG = '$env_name' . '-' . $VERSION;
$NEW_TAG = '$env_name' . '-' . $NEW_VERSION;

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

$branch_name = "staging";
$uri="http://192.168.13.78:8080";

$fix_release = 1 if $ARGV[0] eq "FIX";
$roll_release = 1 if $ARGV[0] eq "ROLL";
die "Is this a FIX or ROLL release, Please tell me!" unless ($fix_release || $roll_release);


`git checkout $branch_name`; die "Cannot checkout into $branch_name, stopped" if $?;

say "Check if $branch_name is in sync with Github.";
#`git fetch origin`; restore_and_die "Cannot fetch origin/$branch_name, stopped" if $?;
#$diff=`git diff --stat origin/$branch_name $branch_name`; restore_and_die "Please synchronize your $branch_name before any deployment, stopped" if $diff;

$diff=`git push origin $branch_name`; restore_and_die "Automatic sync failed. Please sync branch $branch_name before any deployment, stopped" if $diff;


if ($roll_release) {
    say "Roll release: check if master is in sync with Github.";
	#`git fetch origin master`;  restore_and_die "Cannot fetch origin/master, stopped" if $?;
	#$diff=`git diff --stat origin/master master`; restore_and_die "Please synchronize your master before any deployment, stopped" if $diff;
	$diff=`git push origin master`; restore_and_die "Automatic sync failed. Please sync branch master before any deployment, stopped" if $diff;
}

$_ = `git describe --tags --abbrev=0 --match=prod-*`;
print "Current prod tag is $_";
if (/$release_tag_regex/) {
	$new_major = $2;
	$new_minor = $3;
	$new_minor ++;
} else {
	restore_and_die "Wrong prod tag description, stopped";
}

$_ = `git describe --tags --abbrev=0 --match=staging-*`; 
print "Current staging tag is $_";
if (/$release_tag_regex/) {
	$major = $2;
	$minor = $3;
	$env_name = $1;
   	$release = $4;
	$bugfix = $5;
} else {
	restore_and_die "Wrong tag description, stopped";
}

$current_version = interpolate $VERSION;
$bugfix_branchname = "bugfix-$current_version";

if($roll_release) {
	$release ++;
	$bugfix = '0';
	$new_tag = interpolate $NEW_TAG;
	$new_version= interpolate $NEW_VERSION;
	# We would like a linear staging/prod branch without the feature commits
	`git merge --no-ff master -m "$new_tag"`; restore_and_die "Cannot merge master into $branch_name, stopped" if $?;
	say "Merge master into $branch_name, done.";
	say "Sub-version tag has been incremented and the bug count reset.";
   	say qq/Start deployment of the rolling release "$new_tag"./;
} elsif ($fix_release) {
	$bugfix ++;
	$new_tag = interpolate $NEW_TAG;
	$new_version = interpolate $NEW_VERSION;

	`git merge --ff-only $bugfix_branchname`; restore_and_die "Cannot merge bugfix into $branch_name, stopped" if $?;
   	say "Merge $bugfix_branchname into $branch_name, done.";

   	say qq/Start deployment of the fixing release "$new_tag"/;
}


# Build the artifact (will be install whenever sonar is accessible remotely
print
"\tSkip test, build artifact and tomcat deploy steps...\n";


say "About to tag the source with $new_tag";
`git tag $new_tag`; restore_and_die "Cannot tag source, stopped" if $?;

say "Publish_$branch_name into Github";
`git push origin $branch_name`; say "Cannot push $branch_name to origin, stopped" if $?;
`git push origin $new_tag`; restore_and_die "Cannot push new tag to origin, stopped" if $?;

say "Deployment successful.";


`git branch -D $bugfix_branchname`; say "Cannot delete previous local bugfix-branch : $bugfix_branchname" if $?;
`git push origin :$bugfix_branchname`; restore_and_die "Cannot delete previous remote bugfix-branch : origin/$bugfix_branchname" if $?;

$new_bugfix_branchname = "bugfix-$new_version";
`git branch $new_bugfix_branchname`;
`git push origin $new_bugfix_branchname`;

`git checkout master`; die "Cannot checkout master, stopped" if $?;
if($fix_release){
	`git cherry-pick $new_tag`; restore_and_die "Cannot cherry-pick $new_tag, stopped" if $?;
	`git commit --amend -m "$new_tag"`; restore_and_die "Cannot amend the last commit after cherry-picking" if $?;
	`git push origin master`; restore_and_die "Cannot push master to origin, stopped" if $?;
}
;
# say "Start code analysing with sonar";
# `mvn sonar:sonar  -DartifactVersion=$new_version -Dsonar.dynamicAnalysis=reuseReports -Dsonar.skipDesign=true`;

exit 0;
