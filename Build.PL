
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  'build_requires' => {
    'Module::Build' => '0.3601'
  },
  'configure_requires' => {
    'Module::Build' => '0.3601'
  },
  'dist_abstract' => 'Access Perl subs via command line',
  'dist_author' => [
    'Steven Haryanto <stevenharyanto@gmail.com>'
  ],
  'dist_name' => 'Sub-Spec-CmdLine',
  'dist_version' => '0.36',
  'license' => 'perl',
  'module_name' => 'Sub::Spec::CmdLine',
  'recommends' => {},
  'recursive_test_files' => 1,
  'requires' => {
    'Capture::Tiny' => '0',
    'Data::Clone' => '0',
    'Data::Format::Pretty' => '0',
    'Data::Format::Pretty::Console' => '0',
    'Data::Format::Pretty::JSON' => '0',
    'Data::Format::Pretty::PHPSerialization' => '0',
    'Data::Format::Pretty::YAML' => '0',
    'JSON' => '0',
    'List::MoreUtils' => '0',
    'Log::Any' => '0',
    'Sub::Spec' => '0.15',
    'Sub::Spec::BashComplete' => '0.16',
    'Sub::Spec::GetArgs::Argv' => '0.05',
    'Sub::Spec::Runner' => '0.18',
    'Sub::Spec::To::Text::Usage' => '0',
    'Test::More' => '0.96',
    'perl' => '5.010000'
  },
  'script_files' => [
    'bin/runpm'
  ]
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
