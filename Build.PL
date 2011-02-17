
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
  'dist_version' => '0.15',
  'license' => 'perl',
  'module_name' => 'Sub::Spec::CmdLine',
  'recommends' => {},
  'recursive_test_files' => 1,
  'requires' => {
    'Capture::Tiny' => '0',
    'Clone::Any' => '0',
    'Data::Dump::Partial' => '0',
    'Data::Format::Pretty::Console' => '0',
    'JSON' => '0',
    'List::MoreUtils' => '0',
    'Log::Any' => '0',
    'PHP::Serialization' => '0',
    'YAML::Syck' => '0',
    'perl' => '5.010000'
  },
  'script_files' => []
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
