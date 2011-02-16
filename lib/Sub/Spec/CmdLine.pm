package Sub::Spec::CmdLine;
BEGIN {
  $Sub::Spec::CmdLine::VERSION = '0.12';
}
# ABSTRACT: Access Perl subs via command line

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(parse_argv gen_usage format_result run);

# currently we cheat by only parsing a limited subset of schema. this is because
# Data::Sah is not available yet.
sub _parse_schema {
    my ($schema) = @_;

    $schema = [$schema, {}] if !ref($schema);
    die "BUG: Can't parse hash-form schema yet" if ref($schema) ne 'ARRAY';

    my $type = $schema->[0];
    $type =~ s/\*$// and $schema->[1]{required} = 1;
    die "BUG: Can't handle type `$type` yet"
        unless $type =~ /^(int|float|bool|str|array|hash|any)$/;

    {type=>$type, attr_hashes=>[$schema->[1]]};
}

sub parse_argv {
    require Getopt::Long;
    require YAML::Syck; $YAML::Syck::ImplicitTyping = 1;

    my ($argv, $sub_spec, $opts) = @_;
    my $args_spec = $sub_spec->{args} // {};
    $args_spec = { map { $_ => _parse_schema($args_spec->{$_}) }
                       keys %$args_spec };
    $opts //= {};
    $opts->{strict} //= 1;

    my %go_spec;

    my $args = {};
    while (my ($name, $schema) = each %$args_spec) {
        my $opt;
        my @name = ($name);
        push @name, $name if $name =~ s/_/-/g; # allow --foo_bar and --foo-bar
        for (@name) {
            if ($schema->{type} eq 'bool') {
                $opt = "$_!";
            } else {
                $opt = "$_=s";
            }
            #$go_spec{$opt} = sub { $args->{$name[0]} = $_[0] };
            $go_spec{$opt} = \$args->{$name[0]};
        }
    }
    $log->tracef("GetOptions rule: %s", \%go_spec);
    Getopt::Long::Configure("no_pass_through", "no_ignore_case", "permute");
    my $result = Getopt::Long::GetOptionsFromArray($argv, %go_spec);
    unless ($result) {
        die "Incorrect command-line options/arguments\n" if $opts->{strict};
    }

    $log->tracef("tmp args result (after getoptions): %s, argv: %s",
                 $args, $argv);

    # parse YAML in opt values
    for my $k (keys %$args) {
        next unless defined($args->{$k});
        eval { $args->{$k} = YAML::Syck::Load($args->{$k}) };
        if ($@) {
            $log->info("Option --$k doesn't contain valid YAML, ".
                           "assuming it's literal string");
        }
    }

    # parse YAML in remaining @argv
    for my $i (0..@$argv-1) {
        next unless defined($argv->[$i]);
        eval { $argv->[$i] = YAML::Syck::Load($argv->[$i]) };
        if ($@) {
            $log->info("Argument #".($i+1)." doesn't contain valid YAML, ".
                           "assuming it's literal string");
        }
    }

    $log->tracef("tmp args result (after YAML conversion): %s", $args);

    # process arg_pos
  ARGV:
    for my $i (reverse 0..@$argv-1) {
        while (my ($name, $schema) = each %$args_spec) {
            my $ah0 = $schema->{attr_hashes}[0];
            my $o = $ah0->{arg_pos};
            if (defined($o) && $o == $i) {
                if (defined($args->{$name})) {
                    die "You specified option --$name but also argument #".
                        ($i+1)."\n" if $opts->{strict};
                }
                if ($ah0->{arg_greedy}) {
                    $args->{$name} = [splice(@$argv, $i)];
                    last ARGV;
                } else {
                    $args->{$name} = splice(@$argv, $i, 1);
                }
            }
        }
    }

    $log->tracef("tmp args result (after arg_pos processing): %s, argv: %s",
                 $args, $argv);
    if (@$argv) {
        die "Error: extra argument(s): ".join(", ", @$argv)."\n"
            if $opts->{strict};
    }

    # check required args
    while (my ($name, $schema) = each %$args_spec) {
        if ($schema->{attr_hashes}[0]{required} && !defined($args->{$name})) {
            die "Missing required argument: $name\n" if $opts->{strict};
        }
    }

    # cleanup undefined args
    for (keys %$args) {
        delete $args->{$_} unless defined($args->{$_});
    }

    $args;
}

sub gen_usage($;$) {
    require Data::Dump::Partial;
    require List::MoreUtils;

    my ($sub_spec, $opts) = @_;
    $opts //= {};

    my $usage = "";

    my $cmd = $opts->{cmd};
    if ($sub_spec->{name}) {
        $cmd = ($sub_spec->{_package} ? "$sub_spec->{_package}::" : "") .
            $sub_spec->{name};
    }
    if ($sub_spec->{summary}) {
        $usage .= ($cmd ? "$cmd - " : "") . "$sub_spec->{summary}\n\n";
    }

    my $desc = $sub_spec->{description};
    if ($desc) {
        $desc =~ s/^\n+//; $desc =~ s/\n+$//;
        $usage .= "$desc\n\n";
    }

    my $args  = $sub_spec->{args} // {};
    my $rargs = $sub_spec->{required_args};
    $args = { map {$_ => _parse_schema($args->{$_})} keys %$args };
    my $has_cat = grep { $_->{attr_hashes}[0]{arg_category} }
        values %$args;
    my $prev_cat;
    my $noted_star_req;
    for my $name (sort {
        (($args->{$a}{attr_hashes}[0]{arg_category} // "") cmp
             ($args->{$b}{attr_hashes}[0]{arg_category} // "")) ||
                 (($args->{$a}{attr_hashes}[0]{arg_pos} // 9999) <=>
                      ($args->{$b}{attr_hashes}[0]{arg_pos} // 9999)) ||
                          ($a cmp $b) } keys %$args) {
        my $arg = $args->{$name};
        my $ah0 = $arg->{attr_hashes}[0];

        my $cat = $ah0->{arg_category} // "";
        if (!defined($prev_cat) || $prev_cat ne $cat) {
            $usage .= "\n" if defined($prev_cat);
            $usage .= ($cat ? ucfirst("$cat options") :
                           ($has_cat ? "General options" : "Options"));
            $usage .= " (* denotes required options)"
                unless $noted_star_req++;
            $usage .= ":\n";
            $prev_cat = $cat;
        }

        my $arg_desc = "";

        if ($arg->{type} eq 'any') {
            my @schemas = map {_parse_schema($_)} @{$ah0->{of}};
            my @types   = map {$_->{type}} @schemas;
            @types      = sort List::MoreUtils::uniq(@types);
            $arg_desc  .= "[" . join("|", @types) . "]";
        } else {
            $arg_desc  .= "[" . $arg->{type} . "]";
        }

        my $o = $ah0->{arg_pos};
        my $g = $ah0->{arg_greedy};

        $arg_desc .= " $ah0->{summary}" if $ah0->{summary};
        $arg_desc .= " (one of: ".
            Data::Dump::Partial::dumpp($ah0->{in}).")"
                  if defined($ah0->{in});
        $arg_desc .= " (default: ".
            Data::Dump::Partial::dumpp($ah0->{default}).")"
                  if defined($ah0->{default});

        my $desc = $ah0->{description};
        if ($desc) {
            $desc =~ s/^\n+//; $desc =~ s/\n+$//;
            # XXX format/rewrap
            $desc =~ s/^/      /mg;
            $arg_desc .= "\n$desc\n";
        }

        $usage .= sprintf("  --%-25s %s\n",
                          $name . ($ah0->{required} ? "*" : "") .
                              (defined($o) ? " [or arg ".($o+1).
                                  ($g ? "-last":"")."]" : ""),
                          $arg_desc);
    }

    if ($sub_spec->{cmdline_examples}) {
        $usage .= "\nExamples:\n\n";
        my $cmd = $opts->{cmd} // $0;
        for my $ex (@{ $sub_spec->{cmdline_examples} }) {
            $usage .= " % $cmd $ex->{cmd}\n";
            my $desc = $ex->{description};
            if ($desc) {
                $desc =~ s/^\n+//; $desc =~ s/\n+$//;
                $usage .= "\n$desc\n\n";
            }
        }
    }

    $usage;
}

sub format_result {
    require Data::Format::Pretty::Console;
    require JSON;
    require PHP::Serialization;
    require YAML::Syck; $YAML::Syck::ImplicitTyping = 1;

    state $json = JSON->new->allow_nonref;

    my ($res, $format, $opts) = @_;
    $format //= 'text';
    $opts   //= {};

    if ($format eq 'yaml') {
        return YAML::Syck::Dump($res);
    } elsif ($format eq 'json') {
        return $json->encode($res);
    } elsif ($format eq 'php') {
        return PHP::Serialization::serialize($res);
    } elsif ($format =~ /^(text|pretty|nopretty)$/) {
        if (!defined($res->[2])) {
            return $res->[0] == 200 ?
                ($opts->{default_success_message} // "") :
                    "ERROR $res->[0]: $res->[1]\n";
        }
        my $r = $res->[0] == 200 ? $res->[2] : $res;
        if ($format eq 'text') {
            return Data::Format::Pretty::Console::format_pretty($r);
        } elsif ($format eq 'pretty') {
            return Data::Format::Pretty::Console::format_pretty(
                $r, {interactive=>1});
        } elsif ($format eq 'nopretty') {
            return Data::Format::Pretty::Console::format_pretty(
                $r, {interactive=>0});
        }
    }

    die "BUG: Unknown output format `$format`";
}

sub run {
    require Getopt::Long;

    my %args = @_;
    my $exit = $args{exit} // 1;

    # detect (1) if we're being invoked for bash completion, get ARGV from
    # COMP_LINE instead since ARGV given by bash is messed up / different
    my ($comp_words, $comp_cword, $comp_word);
    if ($ENV{COMP_LINE}) {
        eval { require Sub::Spec::BashComplete };
        my $eval_err = $@;
        if ($eval_err) {
            die "Can't load Sub::Spec::BashComplete: $eval_err\n";
        }

        my $res = Sub::Spec::BashComplete::_parse_request();
        $comp_words = $res->{words};
        $comp_cword = $res->{cword};
        $comp_word  = $comp_words->[$comp_cword] // "";

        @ARGV = @$comp_words;

        # drop $0
        if ($comp_cword > 0) {
            shift @$comp_words;
            $comp_cword--;
        }
    }

    my %opts = (format => undef, action => 'run');
    Getopt::Long::Configure("pass_through", "no_ignore_case", "no_permute");
    my %getopts = (
        "--list|l"     => sub { $opts{action} = 'list'     },
        "--version|v"  => sub { $opts{action} = 'version'  },
        "--help|h|?"   => sub { $opts{action} = 'help'     },

        "--text"       => sub { $opts{format} = 'text'     },
        "--yaml"       => sub { $opts{format} = 'yaml'     },
        "--json"       => sub { $opts{format} = 'json'     },
        "--pretty"     => sub { $opts{format} = 'pretty'   },
        "--nopretty"   => sub { $opts{format} = 'nopretty' },
    );
    Getopt::Long::GetOptions(%getopts);

    my $cmd = $args{cmd};
    if (!$cmd) {
        $cmd = $0;
        $cmd =~ s!.+/!!;
    }
    my $subcmds = $args{subcommands};
    my $module;
    my $sub;

    # finding out which module/sub to use
    my $subcmdname;
    my $subcmd;
    my ($complete_arg, $complete_args);
    if ($args{subcommands} && @ARGV) {
        $subcmdname = shift @ARGV;
        $subcmd = $args{subcommands}{$subcmdname};
        # it's ok if user type incomplete subcommand name under completion
        unless ($ENV{COMP_LINE}) {
            $subcmd or die "Unknown subcommand `$subcmdname`, please ".
                "use $cmd -l to list available subcommands\n";
        }
        $module        = $subcmd->{module}        // $args{module};
        $sub           = $subcmd->{sub}           // $subcmdname;
        $complete_arg  = $subcmd->{complete_arg}  // $args{complete_arg};
        $complete_args = $subcmd->{complete_args} // $args{complete_args};
    } else {
        $module        = $args{module};
        $sub           = $args{sub};
        $complete_arg  = $args{complete_arg};
        $complete_args = $args{complete_args};
    }

    # require module and get spec
    my $spec;
    if ($subcmd && $subcmd->{spec}) {
        $spec = ref($subcmd->{spec}) eq 'CODE' ?
            $subcmd->{spec}->(module=>$module, sub=>$sub) :
                $subcmd->{spec};
    } elsif ($args{spec}) {
        $spec = ref($args{spec}) eq 'CODE' ?
            $args{spec}->(module=>$module, sub=>$sub) :
                $args{spec}->();
    } elsif ($module) {
        {
            my $modulep = $args{module};
            $modulep =~ s!::!/!g; $modulep .= ".pm";
            if ($args{require} // 1) {
                eval { require $modulep };
                if ($@) {
                    die $@ unless $ENV{COMP_LINE};
                    last;
                }
            }

            if ($sub) {
                no strict 'refs';
                my $subs = \%{$module."::SUBS"};
                $spec = $subs->{$sub};
                die "Can't find spec for sub $module\::$sub\n"
                    unless $spec || $ENV{COMP_LINE};
            }
        }
    }

    # detect (2) if we're being invoked for bash completion
    if ($ENV{COMP_LINE}) {
        {
            my @general_opts;
            for my $o (keys %getopts) {
                $o =~ s/^--//;
                my @o = split /\|/, $o;
                for (@o) { push @general_opts, length > 1 ? "--$_" : "-$_" }
            }

            if ($spec) {
                print map {"$_\n"}
                    Sub::Spec::BashComplete::bash_complete_spec_arg(
                        $spec,
                        {
                            words    => $comp_words,
                            cword    => $comp_cword,
                            arg_sub  => $complete_arg,
                            args_sub => $complete_args,
                        },
                    );
                last;
            }

            # general options & names of subcommands
            print map {"$_\n"}
                Sub::Spec::BashComplete::_complete_array(
                $comp_word,
                [@general_opts, keys(%{$args{subcommands}})]
            );
        }

        if ($exit) { exit 0 } else { return 0 }
    }

    # handle --list
    if ($opts{action} eq 'list') {
        if ($subcmds) {
            my %cat_subcmds; # (cat1 => {subcmd1=>..., ...}, ...)
            while (my ($k, $v) = each %$subcmds) {
                my $cat = $v->{category} // "";
                $cat_subcmds{$cat} //= {};
                $cat_subcmds{$cat}{$k} = $v;
            }
            my $has_many_cats = scalar(keys %cat_subcmds) > 1;
            my $i = 0;
            for my $cat (sort keys %cat_subcmds) {
                print "\n" if $i++;
                if ($has_many_cats) {
                    print "List of ", ucfirst($cat) || "main",
                        " subcommands:\n";
                } else {
                    print "List of subcommands:\n";
                }
                my $subc = $cat_subcmds{$cat};
                for my $c (sort keys %$subc) {
                    my $sc = $subcmds->{$c};
                    say "  $c", ($sc->{summary} ? " - $sc->{summary}" : "");
                }
            }
        }
        if ($exit) { exit 0 } else { return 0 }
    }

    # handle --version
    if ($opts{action} eq 'version') {
        no strict 'refs';
        my $version = ${$module."::VERSION"} // "?";
        my $rev     = ${$module."::REVISION"};
        say "Version $version", ($rev ? " rev $rev" : "");
        if ($exit) { exit 0 } else { return 0 }
    }

    # handle general --help
    if ($opts{action} eq 'help') {
        if ($args{help}) {
            if (ref($args{help}) eq 'CODE') {
                print $args{help}->();
            } else {
                print $args{help};
            }
        } elsif ($args{subcommands}) {
            say $cmd, ($args{summary} ? " - $args{summary}" : "");
            print <<_;

Usage:
  $cmd --help (or -h, or -?)
  $cmd --list (or -l)
  $cmd --version (or -v)
  $cmd SUBCOMMAND [ARGS ...]
  $cmd SUBCOMMAND --help (or -h, or -?)

Options:
  --help     Show this message
  --list     List subcommands
  --version  Show version
_
        } else {
            print gen_usage($spec, {cmd=>$cmd});
        }
        if ($exit) { exit 0 } else { return 0 }
    }

    die "Please specify a subcommand, ".
        "use $cmd -l to list available subcommands\n"
        unless $module && $sub;

    # handle per-command --help
    if ($subcmd && $ARGV[0] && $ARGV[0] =~ /^(--help|-h|-\?)$/) {
        if ($subcmd->{help}) {
            if (ref($subcmd->{help}) eq 'CODE') {
                print $subcmd->{help}->();
            } else {
                print $subcmd->{help};
            }
        } else {
            print gen_usage($spec, {cmd=>"$cmd $subcmdname"});
        }
        if ($exit) { exit 0 } else { return 0 }
    }

    my $res;
    my $args   = parse_argv(\@ARGV, $spec);
    if ($subcmd && $subcmd->{run}) {
        $res = $subcmd->{run}->(
            module=>$module, sub=>$sub, spec=>$spec,
            args=>$args,
        );
    } else {
        my $subref = \&{$module."::$sub"};
        $res    = $subref->(%$args);
    }

    $log->tracef("opts=%s", \%opts);
    print format_result($res, $opts{format})
        unless $spec->{cmdline_suppress_output};
    my $exit_code = $res->[0] == 200 ? 0 : $res->[0] - 300;
    if ($exit) { exit $exit_code } else { return $exit_code }
}

1;


=pod

=head1 NAME

Sub::Spec::CmdLine - Access Perl subs via command line

=head1 VERSION

version 0.12

=head1 SYNOPSIS

In your module:

 package YourModule;
 our %SUBS;

 $SUBS{foo} = {
     summary => 'Foo!',
     args => {
         arg  => ...,
         arg2 => ...
     },
     ...
 };
 sub foo {
    ...
 }

 ...
 1;

In your script:

 #!/usr/bin/perl
 use Sub::Spec::CmdLine qw(run);
 run(module=>'YourModule', sub=>'foo');

In the command-line:

 % script.pl --help
 % script.pl --arg value --arg2 '[an, array, in, yaml, syntax]' ...

For running multiple subs, in your script:

 use Sub::Spec::CmdLine qw(run);
 run(subcommands => {
     foo => { module=>'YourModule', sub=>'foo'},
     bar => { module=>'YourModule', sub=>'bar'},
     ...
 });

In the command-line:

 % script.pl --help
 % script.pl --list
 % script.pl foo --help
 % script.pl foo --arg value --arg2 ...
 % script.pl bar --blah ...

=head1 DESCRIPTION

This module utilize sub specs (as defined by L<Sub::Spec>) to let your subs be
accessible from the command-line.

This module uses L<Log::Any> logging framework. Use something like
L<Log::Any::App>, etc to see more logging statements for debugging.

NOTE: This module is not ready for public consumption yet. It will be after
L<Data::Sah> and L<Sub::Spec> is released.

=head1 FUNCTIONS

None of the functions are exported by default, but they are exportable.

=head2 parse_argv(\@argv, $sub_spec[, \%opts]) => \%args

Parse command line argument @argv into hash %args, suitable for passing into
subs.

Uses Getopt::Long to parse the result. You can Getopt::Long::Configure
beforehand to modify behaviour (e.g. if you want no_permute).

Note: As with GetOptions, this function modifies its argument, @argv.

Why would one use this function instead of using Getopt::Long directly? Among
other reasons, we want YAML parsing (ability to pass data structures via command
line) and parsing of arg_pos and arg_greedy.

Options in %opts:

=over 4

=item * strict => BOOL (default 1)

If set to 0, will still return parsed argv even if there are errors.

=back

=head2 gen_usage($sub_spec) => TEXT

Generate usage information for a sub (typically used for --help).

=head2 format_result($sub_res[, \%opts]) => TEXT

Format result from sub into various formats

Options:

=over 4

=item * format => FORMAT (optional, default 'text')

Format can be 'text' (pretty text or nonpretty text), 'pretty' (pretty text,
generated by L<Data::Format::Pretty::Console> under interactive=1), 'nopretty'
(also generated by Data::Format::Pretty::Console under interactive=0), 'yaml',
'json', 'php' (generated by L<PHP::Serialization>'s serialize()).

=item * default_success_message => STR (optional, default none)

If output format is text ('text', 'pretty', 'nopretty') and result code is 200
and there is no data returned, this default_success_message is used. Example:
'Success'.

=back

=head2 run(%args)

Run subroutine(s) from the command line, which essentially comprises these
steps:

=over 4

=item * Parse command-line options in @ARGV (using parse_argv())

Also, display help using gen_usage() if given '--help' or '-h' or '-?'.

=item * Call sub

=item * Format the return value from sub (using format_result())

=item * Exit with appropriate exit code

0 if 200, or CODE-300.

=back

Arguments:

=over 4

=item * summary => STR

=item * module => STR

=item * sub => STR

=item * spec => HASH | CODEREF

Instead of trying to look for the spec using B<module> and B<sub>, use the
supplied spec.

=item * help => STRING | CODEREF

Instead of generating help using gen_usage() from the spec, use the supplied
help message (or help code, which is expected to return help text).

=item * subcommands => {NAME => {module=>..., sub=>..., summary=>..., ...}, ...}

B<module> and B<sub> should be specified if you only have one sub to run. If you
have several subs to run, assign each of them to a subcommand, e.g.:

 summary     => 'Maintain a directory containing git repos',
 module      => 'Git::Bunch',
 subcommands => {
   check   => { },
   backup  => { }, # module defaults to main module argument,
   sync    => { }, # sub defaults to the same name as subcommand name
 },

Available argument for each subcommand: module (defaults to main B<module>
argument), sub (defaults to subcommand name), summary, help, category (for
arrangement when listing commands), run, complete_arg, complete_args.

=item * run => CODEREF

Instead of running command by invoking subroutine specified by B<module> and
B<sub>, run this code instead. Code is expected to return a response structure
([CODE, MESSAGE, DATA]).

=item * exit => BOOL (optional, default 1)

If set to 0, instead of exiting with exit(), return the exit code instead.

=item * require => BOOL (optional, default 1)

If set to 0, do not try to require the module.

=item * complete_arg  => {ARGNAME => CODEREF, ...}

Under bash completion, when completing argument value, you can supply a code to
provide its completion. Code will be called with %args containing word, words,
arg, args.

=item * complete_args => CODEREF

Under bash completion, when completing argument value, you can supply a code to
provide its completion. Code will be called with %args containing word, words,
arg, args.

=back

run() can also perform completion for bash (if L<Sub::Spec::BashComplete> is
available). To get bash completion for your B<perlprog>, just type this in bash:

 % complete -C /path/to/perlprog perlprog

You can add that line in bash startup file (~/.bashrc, /etc/bash.bashrc, etc).

=head1 SEE ALSO

L<Sub::Spec>

L<Sub::Spec::Pod>

L<MooseX::Getopt>

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__

