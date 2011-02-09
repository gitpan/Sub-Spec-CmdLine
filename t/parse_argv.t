#!perl

use 5.010;
use strict;
use warnings;
use Log::Any '$log';
use Test::More tests => 13;

use Clone::Any qw(clone);
use Sub::Spec::CmdLine qw(parse_argv);

my $spec = {
    required_args => [qw/arg1 arg2/],
    args => {
        arg1 => [str => {arg_order=>0}],
        arg2 => [str => {arg_order=>1}],
        arg3 => 'str',
    },
};

# XXX check bool arg

test_parse(spec=>$spec, argv=>[qw/--arg1 1 --arg2 2/],
           args=>{arg1=>1, arg2=>2},
           name=>"optional missing = ok");
test_parse(spec=>$spec, argv=>[qw/--arg1 1 --arg2 2/],
           args=>{arg1=>1, arg2=>2},
           name=>"optional given = ok");
test_parse(spec=>$spec, argv=>[qw/1 2/],
           args=>{arg1=>1, arg2=>2},
           name=>"arg_order");
test_parse(spec=>$spec, argv=>[qw/1 2 --arg3 3/],
           args=>{arg1=>1, arg2=>2, arg3=>3},
           name=>"mixed arg_order with opts (1)");
test_parse(spec=>$spec, argv=>[qw/1 --arg2 2/],
           args=>{arg1=>1, arg2=>2},
           name=>"mixed arg_order with opts (2)");
test_parse(spec=>$spec, argv=>[qw/--arg1 1 2/], error=>1,
           name=>"mixed arg_order with opts (clash)");
test_parse(spec=>$spec, argv=>[qw/--arg1 1 --arg2 2 3/], error=>1,
           name=>"extra args given = fails (1)");
test_parse(spec=>$spec, argv=>[qw/1 2 3/], error=>1,
           name=>"extra args given = fails (2)");

test_parse(spec=>$spec, argv=>[qw/arg1/], error=>1,
           name=>"required missing = fails");
test_parse(spec=>$spec, argv=>[qw/--foo bar/], error=>1,
           name=>"unknown args given = fails");
test_parse(spec=>$spec, argv=>['--arg1', 1, '--arg2', '{foo: false}'],
           args=>{arg1=>1, arg2=>{foo=>""}},
           name=>"yaml parsing");
test_parse(spec=>$spec, argv=>['--arg1', 1, '--arg2', '{foo: false'],
           args=>{arg1=>1, arg2=>'{foo: false'},
           name=>"invalid yaml becomes literal");
test_parse(spec=>$spec, argv=>[qw/--arg1 1 --arg2 2/],
           args=>{arg1=>1, arg2=>2},
           name=>"optional missing = ok");

sub test_parse {
    my (%args) = @_;

    my $name = $args{name};
    my $argv = clone($args{argv});
    my $res;
    eval {
        $res = parse_argv($argv, $args{spec});
    };
    my $eval_err = $@;
    if ($args{error}) {
        ok($eval_err, "$name (dies)");
    } else {
        is_deeply($res, $args{args}, $name)
            or diag explain $res;
    }
}

