#!perl

use 5.010;
use strict;
use warnings;
use Log::Any '$log';
use Test::More tests => 8;

use Capture::Tiny      qw(capture);
use Clone::Any         qw(clone);
use Sub::Spec::CmdLine qw(run);

# XXX test require in run()
# XXX test formats

package Foo;
our %SUBS;

$SUBS{ok} = {
    summary => 'Always return ok',
    args => {
        arg1 => ['str*' => {arg_pos=>0}],
        arg2 => ['str*' => {arg_pos=>1}],
        arg3 => 'str',
    },
};
sub ok {
    my %args = @_;
    [200, "OK",
     {"First argument"=>$args{arg1}, "Second argument"=>$args{arg2}}];
}

$SUBS{wantodd} = {
    summary => 'Return error if given an even number',
    args => {
        num => ['int*' => {arg_pos=>0}],
    },
};
sub wantodd {
    my %args = @_;
    if ($args{num} % 2) {
        [200, "OK"];
    } else {
        [400, "You know I hate even numbers, right?"];
    }
}

package main;

test_run(name      => 'single sub',
         args      => {module=>'Foo', sub=>'ok'},
         argv      => [qw/--arg1 1 --arg2 2/],
         exit_code => 0,
         output_re => qr/First argument/,
     );
test_run(name      => 'help message',
         args      => {module=>'Foo', sub=>'ok'},
         argv      => [qw/--help/],
         exit_code => 0,
         output_re => qr/^Options/m,
     );
test_run(name      => 'missing arg = error',
         args      => {module=>'Foo', sub=>'ok'},
         argv      => [qw/--arg3 3/],
         dies      => 1,
     );
test_run(name      => 'unknown arg = error',
         args      => {module=>'Foo', sub=>'ok'},
         argv      => [qw/--arg4/],
         dies      => 1,
     );
test_run(name      => 'exit code from sub res',
         args      => {module=>'Foo', sub=>'wantodd'},
         argv      => [qw/4/],
         exit_code => 100,
         output_re => qr/hate/,
     );

test_run(name      => 'with subcommands',
         args      => {module=>'Foo', subcommands=>{ok=>{}, wantodd=>{}}},
         argv      => [qw/wantodd 3/],
         exit_code => 0,
     );
test_run(name      => 'list subcommands',
         args      => {module=>'Foo', subcommands=>{ok=>{}, wantodd=>{}}},
         argv      => [qw/--list/],
         exit_code => 0,
     );
test_run(name      => 'unknown subcommand = error',
         args      => {module=>'Foo', subcommands=>{ok=>{}, wantodd=>{}}},
         argv      => [qw/foo/],
         dies      => 1,
     );

sub test_run {
    my (%args) = @_;

    local @ARGV = @{$args{argv}};
    my ($stdout, $stderr);
    my $exit_code;
    eval {
        ($stdout, $stderr) = capture {
            $exit_code = run(exit=>0, require=>0, %{$args{args}});
        };
    };
    my $eval_err = $@;

    subtest $args{name} => sub {
        if ($args{dies}) {
            ok($eval_err, "dies");
        } else {
            ok(!$eval_err, "doesn't die") or diag("dies: $eval_err");
        }

        if ($args{exit_code}) {
            is($exit_code, $args{exit_code}, "exit code");
        }

        if ($args{output_re}) {
            like($stdout // "", $args{output_re}, "output_re");
        }
    };
}

