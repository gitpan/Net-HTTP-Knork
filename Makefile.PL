
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;

use File::ShareDir::Install;
install_share dist => "share";


my %WriteMakefileArgs = (
  "ABSTRACT" => "Spore without the whistles and the bells",
  "AUTHOR" => "Emmanuel \"BHS_error\" Peroumalnaik",
  "BUILD_REQUIRES" => {},
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30",
    "File::ShareDir::Install" => "0.03"
  },
  "DISTNAME" => "Net-HTTP-Knork",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "Net::HTTP::Knork",
  "PREREQ_PM" => {
    "Carp" => 0,
    "Class::Method::Modifiers" => 0,
    "DDP" => 0,
    "Data::Rx" => 0,
    "File::ShareDir" => 0,
    "HTTP::Response" => 0,
    "JSON" => 0,
    "LWP::UserAgent" => 0,
    "Moo" => 0,
    "Moo::Role" => 0,
    "Sub::Install" => 0,
    "Subclass::Of" => 0,
    "Test::Deep" => 0,
    "Test::Exception" => 0,
    "Test::LWP::UserAgent" => 0,
    "Try::Tiny" => 0,
    "URI" => 0
  },
  "TEST_REQUIRES" => {},
  "VERSION" => "0.07",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


my %FallbackPrereqs = (
  "Carp" => 0,
  "Class::Method::Modifiers" => 0,
  "DDP" => 0,
  "Data::Rx" => 0,
  "File::ShareDir" => 0,
  "HTTP::Response" => 0,
  "JSON" => 0,
  "LWP::UserAgent" => 0,
  "Moo" => 0,
  "Moo::Role" => 0,
  "Sub::Install" => 0,
  "Subclass::Of" => 0,
  "Test::Deep" => 0,
  "Test::Exception" => 0,
  "Test::LWP::UserAgent" => 0,
  "Try::Tiny" => 0,
  "URI" => 0
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  delete $WriteMakefileArgs{TEST_REQUIRES};
  delete $WriteMakefileArgs{BUILD_REQUIRES};
  $WriteMakefileArgs{PREREQ_PM} = \%FallbackPrereqs;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);

{
package
MY;
use File::ShareDir::Install qw(postamble);
}


