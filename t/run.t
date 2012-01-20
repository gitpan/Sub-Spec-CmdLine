#!perl

use 5.010;
use strict;
use warnings;
use Log::Any '$log';
use Test::More 0.96;

use Capture::Tiny      qw(capture);
use Data::Clone        qw(clone);
use Sub::Spec::CmdLine qw(run);

# XXX test require in run()
# XXX test formats

package Foo;
our $VERSION = "0.01";
our %SPEC;

$SPEC{ok} = {
    summary => 'Always return ok',
    args => {
        arg1 => ['str*' => {arg_pos=>0, in=>[qw/a b c d/]}],
        arg2 => ['str*' => {arg_pos=>1}],
        arg3 => 'str',
    },
};
sub ok {
    my %args = @_;
    [200, "OK",
     {"First argument"=>$args{arg1}, "Second argument"=>$args{arg2}}];
}

$SPEC{want_odd} = {
    summary => 'Return error if given an even number',
    args => {
        num => ['int*' => {arg_pos=>0}],
    },
};
sub want_odd {
    my %args = @_;
    if ($args{num} % 2) {
        [200, "OK"];
    } else {
        [400, "You know I hate even numbers, right?"];
    }
}

package main;

subtest 'completion' => sub {
    plan skip_all => 'Sub::Spec::BashComplete is not available'
        unless eval { require Sub::Spec::BashComplete };
    unless ($Sub::Spec::BashComplete::VERSION >= '0.10') {
        my $msg = 'Sub::Spec::BashComplete version too old (< 0.10)';
        if ($ENV{RELEASE_TESTING}) {
            die $msg;
        } else {
            plan skip_all => $msg;
        }
    }

    test_complete(
        name        => 'arg name (single sub)',
        argv        => [],
        args        => {module=>'Foo', sub=>'ok'},
        comp_line   => 'CMD -',
        comp_point0 => '     ^',
        result      => [qw(--help -h -\? --arg1 --arg2 --arg3)],
    );
    test_complete(
        name        => 'arg value from arg spec "in" (single sub)',
        argv        => [],
        args        => {module=>'Foo', sub=>'ok'},
        comp_line   => 'CMD ',
        comp_point0 => '    ^',
        result      => [qw(a b c d)],
    );
    test_complete(
        name        => 'arg value from "complete_args" (single sub)',
        argv        => [],
        args        => {module=>'Foo', sub=>'ok',
                        complete_args=>sub {qw(e f g h)}},
        comp_line   => 'CMD arg1 ',
        comp_point0 => '         ^',
        result      => [qw(e f g h)],
    );
    test_complete(
        name        => 'arg value from "complete_arg" (single sub)',
        argv        => [],
        args        => {module=>'Foo', sub=>'ok',
                        complete_arg=>{arg2=>sub{qw(e f g h)}}},
        comp_line   => 'CMD arg1 ',
        comp_point0 => '         ^',
        result      => [qw(e f g h)],
    );
};

test_run(name      => 'single sub',
         args      => {module=>'Foo', sub=>'ok'},
         argv      => [qw/--arg1 1 --arg2 2/],
         exit_code => 0,
         output_re => qr/First argument/,
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
         args      => {module=>'Foo', sub=>'want_odd'},
         argv      => [qw/4/],
         exit_code => 100,
         output_re => qr/hate/,
     );

test_run(name      => 'subcommands',
         args      => {module=>'Foo', subcommands=>{ok=>{}, want_odd=>{}}},
         argv      => [qw/want_odd 3/],
         exit_code => 0,
     );

test_run(name      => 'unknown subcommand = error',
         args      => {module=>'Foo', subcommands=>{ok=>{}, want_odd=>{}}},
         argv      => [qw/foo/],
         dies      => 1,
     );

test_run(name      => 'arg: dash_to_underscore=0',
         args      => {module=>'Foo', subcommands=>{ok=>{}, want_odd=>{}}},
         argv      => [qw/want-odd 3/],
         dies      => 1,
     );
test_run(name      => 'arg: dash_to_underscore=1',
         args      => {dash_to_underscore=>1,
                       module=>'Foo', subcommands=>{ok=>{}, want_odd=>{}}},
         argv      => [qw/want-odd 3/],
         exit_code => 0,
     );

for (qw(--help -h -?)) {
    test_run(name      => "help ($_)",
             args      => {module=>'Foo', sub=>'ok'},
             argv      => [$_],
             exit_code => 0,
             output_re => qr/^Options/m,
         );
}

test_run(name      => "general option (--version) before subcommand name",
         args      => {module=>'Foo', subcommands=>{ok=>{}, want_odd=>{}}},
         argv      => [qw/--version want_odd --num 4/],
         exit_code => 0,
         output_re => qr/version 0\.01/m,
     );
test_run(name      => "general option (--help) after subcommand name",
         args      => {module=>'Foo', subcommands=>{ok=>{}, want_odd=>{}}},
         argv      => [qw/want_odd --num 4 --help/],
         exit_code => 0,
         output_re => qr/^Options/m,
     );

for (qw(--version -v)) {
    test_run(name      => "version ($_)",
             args      => {module=>'Foo', sub=>'ok'},
             argv      => [$_],
             exit_code => 0,
             output_re => qr/version 0\.01/m,
         );
}

for (qw(--list -l)) {
    test_run(name      => "list ($_)",
             args      => {module=>'Foo', subcommands=>{ok=>{}, want_odd=>{}}},
             argv      => [$_],
             exit_code => 0,
         );
}

my $subc = sub {
    my %args = @_;
    my $name = $args{name};

    my $s = {ok=>{}, want_odd=>{}};
    if ($args{name}) {
        $s->{$name};
    } else {
        $s;
    }
};
test_run(name      => 'coderef subcommands (a)',
         args      => {module=>'Foo', subcommands=>$subc},
         argv      => [qw/ok --arg1 1 --arg2 2/],
         exit_code => 0,
     );
test_run(name      => 'coderef subcommands (b)',
         args      => {module=>'Foo', subcommands=>$subc},
         argv      => [qw/want_odd 4/],
         exit_code => 100,
         output_re => qr/hate/,
     );
test_run(name      => 'coderef subcommands (c)',
         args      => {module=>'Foo', subcommands=>$subc},
         argv      => [qw/foo/],
         dies      => 1,
     );
# XXX test arg: load_module
# XXX test arg: run (main / per-subcommand)
# XXX test arg: help text (main / per-subcommand)
# XXX test arg: help coderef
# XXX test arg: spec (main / per-subcommand)
# XXX test arg: spec coderef
# XXX test arg: complete_arg, complete_args (main / per-subcommand)
# XXX test arg: allow_unknown_args (main / per-subcommand)
# XXX test runpm -I (or move to run()?)

# XXX test arg: undo

done_testing();

sub test_run {
    my (%args) = @_;

    local @ARGV = @{$args{argv}};
    my ($stdout, $stderr);
    my $exit_code;
    eval {
        if ($args{output_re}) {
            ($stdout, $stderr) = capture {
                $exit_code = run(exit=>0, load=>0, %{$args{args}});
            };
        } else {
            $exit_code = run(exit=>0, load=>0, %{$args{args}});
        }
    };
    my $eval_err = $@;

    subtest $args{name} => sub {
        if ($args{dies}) {
            ok($eval_err || ref($eval_err), "dies");
        } else {
            ok(!$eval_err, "doesn't die") or diag("dies: $eval_err");
        }

        if ($args{exit_code}) {
            is($exit_code, $args{exit_code}, "exit code");
        }

        if ($args{output_re}) {
            like($stdout // "", $args{output_re}, "output_re")
                or diag("output is $stdout");
        }
    };
}

sub test_complete {
    my (%args) = @_;

    local @ARGV = @{$args{argv}};
    local $ENV{COMP_LINE}  = $args{comp_line};
    local $ENV{COMP_POINT} = index($args{comp_point0}, "^");

    my ($stdout, $stderr);
    my $exit_code;
    ($stdout, $stderr) = capture {
        $exit_code = run(exit=>0, load=>0, %{$args{args}});
    };

    subtest "completion: $args{name}" => sub {
        is($exit_code, 0, "exit code = 0");
        is($stdout // "", join("", map {"$_\n"} @{$args{result}}), "result");
    };
}

