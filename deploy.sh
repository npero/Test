#!/usr/bin/perl

use feature qw(say);
use Term::ReadKey;
use FindBin;
use Getopt::Long;

$major_flag='';
GetOptions ("major-build"  => \$major_flag);

$release_tag_regex=qr/(\w+)-(\d)\.(\d+)\.(\d+)\.?(\d*)/;
$STAGING_VERSION = '$major.$minor.$release.$bugfix';
$STAGING_TAG = '$env_name' . '-' . $STAGING_VERSION;
$PROD_VERSION = '$major.$minor.$hotfix';
$PROD_TAG = '$env_name' . '-' . $PROD_VERSION;

# Pass a CONSTANT string containing $variable to interpolate dynamically.
sub interpolate {
	eval "qq/$_[0]/";
}

sub restore_and_die {
	`git checkout master`;
	die $_[0];
}

sub tag {
   `git tag $_[0]`; restore_and_die "Cannot tag source, stopped" if $?;
}

sub checkout{
    my($branch_name) = $_[0];
    `git checkout $branch_name`; die "Cannot checkout into $branch_name, stopped" if $?;
}

sub push {
    my($branch_name) = $_[0];
    `git push origin $branch_name`; restore_and_die "Cannot push $branch_name to origin, stopped" if $?;
}

sub check_sync{
    my($branch_name) = $_[0];
    say "Check if $branch_name is in sync with Github.";
    `git fetch origin $branch_name`; restore_and_die "Cannot fetch origin/$branch_name, stopped" if $?;
    $diff=`git diff --stat origin/$branch_name $branch_name`; restore_and_die "Please synchronize your $branch_name before any deployment, stopped" if $diff;
}

sub merge_no_ff{
    my($upstream) = $_[0];
    # We would like a linear $branch_name branch without the feature commits
    `git merge --no-ff $upstream -m "$new_tag"`; restore_and_die "Cannot merge $upstream into $branch_name, stopped" if $?;
    say "Merge $upstream into $branch_name, done.";
    # say "Release tag has been incremented and the bugfix reset.";
    say "Tag number has been incremented.";
    say qq/Start deployment of the rolling release "$new_tag"./;
}

$working_dir = "$FindBin::RealBin/../../";
chdir($working_dir);

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

check_sync("master");check_sync("staging");check_sync("prod");

# Getting current prod tag
`git checkout prod`; die "Cannot checkout into prod, stopped" if $?;
$_ = `git describe --tags --abbrev=0`;
print "Current prod tag is $_";
if (/$release_tag_regex/) {
	$env_name = $1;
	$major = $2;
	$minor = $3;
   	$hotfix = $4
} else {
	restore_and_die "Wrong prod tag description, stopped";
}

$prod_current_version = interpolate $PROD_VERSION;

# Getting current staging tag
`git checkout staging`; die "Cannot checkout into staging, stopped" if $?;
$_ = `git describe --tags --abbrev=0`;
print "Current staging tag is $_";
if (/$release_tag_regex/) {
	$env_name = $1;
	$major = $2;
	$minor = $3;
   	$release = $4;
	$bugfix = $5;
} else {
	restore_and_die "Wrong staging tag description, stopped";
}

$staging_current_version = interpolate $STAGING_VERSION;


if ($branch_name eq "staging") {
   if($roll_release) {
        checkout $branch_name;
        $release ++;
        $bugfix = '0';
        $new_tag = interpolate $STAGING_TAG;
        $new_version= interpolate $STAGING_VERSION;
        merge_no_ff "master";

        say qq/Start deployment of the rolling release "$new_tag"/;

   } elsif ($fix_release) {
        $bugfix ++;
        $new_tag = interpolate $STAGING_TAG;
        $new_version= interpolate $STAGING_VERSION;

        $copy_new_tag = $new_tag + '(s)';

        say qq/Start deployment of the fixing release "$new_tag"/;

   }


} elsif ($branch_name eq "prod") {
    if($roll_release) {
        checkout $branch_name;
        if($major_flag){
            $major ++;
            $minor = '0';
        }
        else{
            $minor ++;
        }
        $hotfix = '0';
        $new_tag = interpolate $PROD_TAG;
        $new_version= interpolate $PROD_VERSION;
        merge_no_ff "staging";

        say qq/Start deployment of the rolling release "$new_tag"/;

    } elsif ($fix_release) {
        $hotfix ++;
        $new_tag = interpolate $PROD_TAG;
        $new_version = interpolate $PROD_VERSION;

        $copy_new_tag = $new_tag + "(p)";

        say qq/Start deployment of the fixing release "$new_tag";

    }

}

   # Build the artifact (will be install whenever sonar is accessible remotely
   print
   "\t - run all tests,\n\t - build the artifact,\n\t - send it to the remote server to be deployed.\n This takes a while ...\n";
   `mvn clean tomcat:redeploy -DfailIfNoTests=false -DbaseUri=$uri -DartifactVersion=$new_version -Dtomcat.password=$password`;
   if ($?) {
        say "Redeploy FAILED!";
        `git reset --hard HEAD^`;
        print "\t$branch_name has been reset to previous state. " unless $?;
        restore_and_die "\tSource won't be tagged, stopped";
   }

   say "Deploy of $new_version into $branch_name succeeds.";

   say "About to tag the source with $new_tag";
   tag $new_tag;

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
push "master";
push $branch_name;
push $new_tag;

if($fix_release) {

    if($branch_name eq "staging"){
         checkout "master";
         `git cherry-pick $new_tag`;
         tag $copy_new_tag;

    }
    elsif($branch_name eq "prod"){
         checkout "staging";
         `git cherry-pick $new_tag`;
         tag $copy_new_tag;
    }
}

say "Deployment successful.";

checkout "master";

# say "Start code analysing with sonar";
# `mvn sonar:sonar  -DartifactVersion=$new_version -Dsonar.dynamicAnalysis=reuseReports -Dsonar.skipDesign=true`;

exit 0;
