#!perl

use 5.010;
use strict;
use warnings;
use Log::Any '$log';
use Test::More 0.96;

use Data::Clone        qw(clone);
use Sub::Spec::CmdLine qw(parse_argv);

my $spec = {
    args => {
        arg1 => ['str*' => {arg_pos=>0}],
        arg2 => ['str*' => {arg_pos=>1}],
        arg3 => 'str',
        arg4 => 'array',
        arg5 => 'hash',
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
           name=>"arg_pos");
test_parse(spec=>$spec, argv=>[qw/1 2 --arg3 3/],
           args=>{arg1=>1, arg2=>2, arg3=>3},
           name=>"mixed arg_pos with opts (1)");
test_parse(spec=>$spec, argv=>[qw/1 --arg2 2/],
           args=>{arg1=>1, arg2=>2},
           name=>"mixed arg_pos with opts (2)");
test_parse(spec=>$spec, argv=>[qw/--arg1 1 2/], error=>1,
           name=>"mixed arg_pos with opts (clash)");
test_parse(spec=>$spec, argv=>[qw/--arg1 1 --arg2 2 3/], error=>1,
           name=>"extra args given = fails (1)");
test_parse(spec=>$spec, argv=>[qw/1 2 3/], error=>1,
           name=>"extra args given = fails (2)");

test_parse(spec=>$spec, argv=>[qw/arg1/], error=>1,
           name=>"required missing = fails");
test_parse(spec=>$spec, argv=>[qw/--foo bar/], error=>1,
           name=>"unknown args given = fails");
test_parse(spec=>$spec, argv=>[qw/--arg1 1 --arg2 2/],
           args=>{arg1=>1, arg2=>2},
           name=>"optional missing = ok");

test_parse(spec=>$spec, argv=>['--arg1', '{foo: false}',
                               '--arg2', '',
                               '--arg5', '{foo: false}'],
           args=>{arg1=>'{foo: false}', arg2=>'', arg5=>{foo=>""}},
           name=>"yaml parsing, done on nonscalars");
test_parse(spec=>$spec, argv=>['--arg1', '{foo: false}',
                               '--arg2', '',
                               '--arg5', '{foo: false'],
           error=>1,
           name=>"yaml syntax error");

{
    my $extra;
    test_parse(spec=>$spec, argv=>[qw/--arg1 1 --arg2 2 --extra/],
               opts=>{extra_getopts=>{extra=>sub{$extra=5}}},
               args=>{arg1=>1, arg2=>2},
               post_test=>sub {
                   is($extra, 5, "extra getopt is executed");
               },
               name=>"opt: extra_getopts",
           );
}

test_parse(spec=>{args=>{arg1=>'str*'}}, argv=>[qw/--arg1 1 --arg2 2/],
           opts=>{strict=>1}, # the default
           error=>1,
           name=>"opt: strict=1",
       );
test_parse(spec=>{args=>{arg1=>'str*'}}, argv=>[qw/--arg1 1 --arg2 2/],
           opts=>{strict=>0},
           args=>{arg1=>1},
           name=>"opt: strict=0",
       );

# XXX test --foo-bar as --foo_bar alias

DONE_TESTING:
done_testing();

sub test_parse {
    my (%args) = @_;

    subtest $args{name} => sub {
        my $argv = clone($args{argv});
        my $res;
        my $opts = $args{opts} // {};
        eval {
            $res = parse_argv($argv, $args{spec}, $opts);
        };
        my $eval_err = $@;
        diag "eval_err = $eval_err" if $eval_err;
        if ($args{error}) {
            ok($eval_err, "dies");
        } else {
            is_deeply($res, $args{args}, "result")
                or diag explain $res;
        }

        if ($args{post_test}) {
            $args{post_test}->();
        }
    }
}

