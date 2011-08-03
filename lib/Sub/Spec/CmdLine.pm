package Sub::Spec::CmdLine;
BEGIN {
  $Sub::Spec::CmdLine::VERSION = '0.34';
}
# ABSTRACT: Access Perl subs via command line

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(gen_usage format_result run);

use Sub::Spec::GetArgs::Argv qw(get_args_from_argv);
use Sub::Spec::Utils; # tmp, for _parse_schema

sub _parse_schema {
    Sub::Spec::Utils::_parse_schema(@_);
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
                           ($has_cat ? "General options" :
                                ($opts->{options_name} ?
                                     "$opts->{options_name} options" :
                                         "Options")));
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

        my $aliases = $ah0->{arg_aliases};
        if ($aliases) {
            $arg_desc .= "\n";
            for (sort keys %$aliases) {
                my $alinfo = $aliases->{$_};
                $arg_desc .= join(
                    "",
                    "      ",
                    (length == 1 ? "-$_" : "--$_"), " ",
                    $alinfo->{summary} ? $alinfo->{summary} :
                        "is alias for '$name'",
                    "\n"
                );
            }
        }

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

sub _run_list {
    my ($subcommands, $args) = @_;

    return unless $subcommands;

    if (ref($subcommands) eq 'CODE') {
        $subcommands = $subcommands->(args=>$args);
        die "Error: subcommands code didn't return a hashref\n"
            unless ref($subcommands) eq 'HASH';
    }

    my %percat_subc; # (cat1 => {subcmd1=>..., ...}, ...)
    while (my ($scn, $sc) = each %$subcommands) {
        my $cat = $sc->{category} // "";
        $percat_subc{$cat}       //= {};
        $percat_subc{$cat}{$scn}   = $sc;
    }
    my $has_many_cats = scalar(keys %percat_subc) > 1;

    my $i = 0;
    for my $cat (sort keys %percat_subc) {
        print "\n" if $i++;
        if ($has_many_cats) {
            print "List of ", ucfirst($cat) || "main",
                " subcommands:\n";
        } else {
            print "List of subcommands:\n";
        }
        my $subc = $percat_subc{$cat};
        for my $scn (sort keys %$subc) {
            my $sc = $subc->{$scn};
            say "  $scn", ($sc->{summary} ? " - $sc->{summary}" : "");
        }
    }
}

sub _run_version {
    my ($module, $cmd, $summary) = @_;

    # get from module's $VERSION
    no strict 'refs';
    my $version = ${$module."::VERSION"} // "?";
    my $rev     = ${$module."::REVISION"};

    say "$cmd version ", $version, ($rev ? " rev $rev" : "");
}

sub _run_completion {
    my %args = @_;

    my @general_opts;
    for my $o (keys %{$args{getopts}}) {
        $o =~ s/^--//;
        my @o = split /\|/, $o;
        for (@o) { push @general_opts, length > 1 ? "--$_" : "-$_" }
    }

    my $spec  = $args{spec};
    my $subc  = $args{subcommand};
    my $subcn = $args{subcommand_name};
    my $words = $args{words};
    my $cword = $args{cword};

    # whether we should complete arg names/values or general opts + subcommands
    # name
    my $do_arg;
    {
        # we can't do arg unless we already get the spec
        if (!$spec) {
            $log->trace("not do_arg because there is no spec");
            last;
        }

        # single-sub directly complete arg names/values
        if (!$subc) {
            $log->trace("do_arg because single sub");
            $do_arg++; last;
        }

        # multiple-sub, just typing "CMD subc ^" (space already typed)
        if ($cword > 0 && $args{space_typed} && $subcn) {
            $log->trace("do_arg because last word typed (+space) is ".
                            "subcommand name");
            $do_arg++; last;
        }

        # multiple-sub, already typing subc in past words
        if ($cword > 0 && !$args{space_typed} && $words->[$cword] ne $subcn) {
            $log->trace("do_arg because subcommand name has been typed ".
                            "in past words");
            $do_arg++; last;
        }

        $log->tracef("not do_arg, cword=%d, words=%s, subcommand_name=%s, ".
                         "space_typed=%s",
                     $cword, $words, $subcn, $args{space_typed});
    }
    if ($do_arg) {
        $log->trace("Complete subcommand argument names & values");

        # remove subcommand name and general options from words so it doesn't
        # interfere with matching spec args
        my $i = 0;
        while ($i < @$words) {
            if ($words->[$i] ~~ @general_opts || $words->[$i] eq $subcn) {
                splice @$words, $i, 1;
                $cword-- unless $cword <= $i;
                next;
            } else {
                $i++;
            }
        }
        $log->tracef("cleaned words=%s, cword=%d", $words, $cword);

        return Sub::Spec::BashComplete::bash_complete_spec_arg(
            $spec,
            {
                words            => $words,
                cword            => $cword,
                arg_sub          => $args{arg_sub},
                args_sub         => $args{args_sub},
                custom_completer =>
                    ($subc ? $subc->{custom_completer} :
                         undef) // $args{parent_args}{custom_completer}
            },
        );
    } else {
        $log->trace("Complete general options & names of subcommands");
        my $subcommands = $args{parent_args}{subcommands};
        if (ref($subcommands) eq 'CODE') {
            $subcommands = $subcommands->(parent_args=>$args{parent_args});
            die "Error: subcommands code didn't return hashref (2)\n"
                unless ref($subcommands) eq 'HASH';
        }
        return Sub::Spec::BashComplete::_complete_array(
            $args{word},
            [@general_opts, keys(%$subcommands)]
        );
    }
}

# returns help text
sub _run_help {
    my ($help, $spec, $cmd, $summary, $argv) = @_;

    my $out = "";

    #$out .= $cmd . ($summary ? " - $summary" : "") . "\n\n";

    if ($help) {
        if (ref($help) eq 'CODE') {
            $out .= $help->(
                spec=>$spec, cmd=>$cmd,
                argv=>$argv,
            );
        } else {
            $out .= $help;
        }
    } elsif ($spec) {
        $out .= gen_usage($spec, {cmd=>$cmd});
    } else {
            $out .= <<_;
Usage:
  To get general help:
    $cmd --help (or -h)
  To list subcommands:
    $cmd --list (or -l)
  To show version:
    $cmd --version (or -v)
  To get help on a subcommand:
    $cmd --help SUBCOMMAND
  To run a subcommand:
    $cmd SUBCOMMAND [ARGS ...]

_
    }
    $out;
}

sub run {
    $log->trace("-> CmdLine's run()");
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
    }

    my %opts = (format => undef, action => 'run');
    my $old_go_opts = Getopt::Long::Configure(
        "pass_through", "no_ignore_case", "no_permute");
    my %getopts = (
        "list"       => sub {
            $Sub::Spec::GetArgs::Argv::_pa_skip_check_required_args++;
            $opts{action} = 'list'     },
        "version"    => sub {
            $Sub::Spec::GetArgs::Argv::_pa_skip_check_required_args++;
            $opts{action} = 'version'  },
        "help"       => sub {
            $Sub::Spec::GetArgs::Argv::_pa_skip_check_required_args++;
            $opts{action} = 'help'     },

        "text"       => sub { $opts{format} = 'text'     },
        "yaml"       => sub { $opts{format} = 'yaml'     },
        "json"       => sub { $opts{format} = 'json'     },
        "pretty"     => sub { $opts{format} = 'pretty'   },
        "nopretty"   => sub { $opts{format} = 'nopretty' },
    );
    # aliases. we don't use "version|v" etc so the key can be compared with spec
    # arg in get_args_from_argv()
    $getopts{l} = $getopts{list};
    $getopts{v} = $getopts{version};
    $getopts{h} = $getopts{help};
    $getopts{'please_help_me|?'} = $getopts{help}; # Go::L doesn't accept '?'

    Getopt::Long::GetOptions(%getopts);
    Getopt::Long::Configure($old_go_opts);

    my $cmd = $args{cmd};
    if (!$cmd) {
        $cmd = $0;
        $cmd =~ s!.+/!!;
    }
    my $subcommands = $args{subcommands};
    my $module;
    my $sub;

    # finding out which module/sub to use
    my $subc;
    my $subc_name;
    my $load;
    if ($subcommands && @ARGV) {
        $subc_name = shift @ARGV;
        $subc_name =~ s/-/_/g if $args{dash_to_underscore};
        $subc      = ref($subcommands) eq 'CODE' ?
            $subcommands->(name=>$subc_name, args=>\%args) :
            $subcommands->{$subc_name};
        # it's ok if user type incomplete subcommand name under completion
        unless ($ENV{COMP_LINE}) {
            $subc or die "Unknown subcommand `$subc_name`, please ".
                "use $cmd -l to list available subcommands\n";
        }
        $module        = $subc->{module}        // $args{module};
        $sub           = $subc->{sub}           // $subc_name;
        $load          = $subc->{load}          // $args{load} // 1;
    } else {
        $module        = $args{module};
        $sub           = $args{sub};
        $load          = $args{load}            // 1;
    }

    # require module and get spec
    my $spec;
    if ($subc && $subc->{spec}) {
        $spec = ref($subc->{spec}) eq 'CODE' ?
            $subc->{spec}->(module=>$module, sub=>$sub) :
                $subc->{spec};
    } elsif ($args{spec}) {
        $spec = ref($args{spec}) eq 'CODE' ?
            $args{spec}->(module=>$module, sub=>$sub) :
                $args{spec};
    } elsif ($module) {
        {
            my $modulep = $args{module};
            $modulep =~ s!::!/!g; $modulep .= ".pm";
            if ($load) {
                eval { require $modulep };
                if ($@) {
                    die $@ unless $ENV{COMP_LINE};
                    last;
                }
            }

            if ($sub) {
                no strict 'refs';
                my $subs = \%{$module."::SPEC"};
                $spec = $subs->{$sub};
                die "Can't find spec for sub $module\::$sub\n"
                    unless $spec || $ENV{COMP_LINE};
            }
        }
    }

    # now that we have spec, detect (2) if we're being invoked for bash
    # completion and do completion, and exit.
    if ($ENV{COMP_LINE}) {
        # user has typed 'CMD subc ^' instead of just 'CMD subc^', in the latter
        # case we still need to complete subcommands name.
        my $space_typed = !defined($comp_words->[$comp_cword]);

        my $complete_arg;
        my $complete_args;
        if ($subc) {
            $complete_arg    = $subc->{complete_arg};
            $complete_args   = $subc->{complete_args};
        }
        $complete_arg      //= $args{complete_arg};
        $complete_args     //= $args{complete_args};
        my @res = _run_completion(
            space_typed     => $space_typed,
            parent_args     => \%args,
            spec            => $spec,
            getopts         => \%getopts,
            words           => $comp_words,
            cword           => $comp_cword,
            word            => $comp_word ,
            arg_sub         => $complete_arg,
            args_sub        => $complete_args,
            subcommand      => $subc,
            subcommand_name => $subc_name,
        );
        $log->tracef("completion result: %s", \@res);
        print map {Sub::Spec::BashComplete::_add_slashes($_), "\n"} @res;
        #print map {"$_\n"} @res;
        if ($exit) { exit 0 } else { return 0 }
    }

    # parse argv
    my $args;
    if ($spec && $opts{action} eq 'run') {
        my %ga_args = (argv=>\@ARGV, spec=>$spec);
        $ga_args{strict} = 0
            if $subc->{allow_unknown_args} // $args{allow_unknown_args};

        # this allows us to catch --help, --version, etc specified after
        # subcommand name (if it doesn't collide with any spec arg). for
        # convenience, e.g.: allowing 'cmd subcmd --help' in addition to 'cmd
        # --help subcmd'.
        $ga_args{extra_getopts} = \%getopts;
        $args = get_args_from_argv(%ga_args);
    }

    # handle --list
    if ($opts{action} eq 'list') {
        _run_list($subcommands, \%args);
        if ($exit) { exit 0 } else { return 0 }
    }

    # handle --version
    if ($opts{action} eq 'version') {
        _run_version($module, $cmd, $args{summary});
        if ($exit) { exit 0 } else { return 0 }
    }

    # handle --help
    if ($opts{action} eq 'help') {
        if ($spec) {
            print _run_help(
                $subc->{help}, $spec,
                ($subc_name ? "$cmd $subc_name" : $cmd),
                ($subc ? $subc->{summary} : $args{summary}),
                 \@ARGV);
        if ($exit) { exit 0 } else { return 0 }
        } else {
            print _run_help(
                $args{help}, undef, $cmd,
                $subc ? $subc->{summary} : $args{summary},
                \@ARGV, undef);
        }
        if ($exit) { exit 0 } else { return 0 }
    }

    die "Please specify a subcommand, ".
        "use $cmd -l to list available subcommands\n"
            unless $spec;

    # finally, run!
    my $res;
    if ($subc && $subc->{run}) {
        # use run routine instead if supplied
        $res = $subc->{run}->(
            subcommand_name => $subc_name,
            module   => $module,
            sub      => $sub,
            spec     => $spec,
            sub_args => $args,
        );
    } else {
        # run sub
        {
            require Sub::Spec::Runner;
            my $runner = Sub::Spec::Runner->new;
            $runner->load_modules($load);
            eval { $runner->add("$module\::$sub", $args) };
            my $eval_err = $@;
            if ($eval_err) {
                chomp($eval_err);
                $res = [412, $eval_err];
                last;
            }
            $res = $runner->run(use_last_res=>1);
        }
    }

    my $exit_code = $res->[0] == 200 ? 0 : $res->[0] - 300;

    # output
    $log->tracef("res=%s", $res);
    $log->tracef("opts=%s", \%opts);
    print format_result($res, $opts{format})
        unless $spec->{cmdline_suppress_output} && !$exit_code;

    $log->trace("<- CmdLine's run()");
    if ($exit) { exit $exit_code } else { return $exit_code }
}

1;


=pod

=head1 NAME

Sub::Spec::CmdLine - Access Perl subs via command line

=head1 VERSION

version 0.34

=head1 SYNOPSIS

In your module:

 package YourModule;
 our %SPEC;

 $SPEC{foo} = {
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

=head1 FUNCTIONS

None of the functions are exported by default, but they are exportable.

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

=item * Parse command-line options in @ARGV (using Sub::Spec::GetArgs::Argv)

Also, display help using gen_usage() if given '--help' or '-h' or '-?'.

See L<Sub::Spec::GetArgs::Argv> for details on parsing.

=item * Call sub

=item * Format the return value from sub (using format_result())

=item * Exit with appropriate exit code

0 if 200, or CODE-300.

=back

Arguments (* denotes required arguments):

=over 4

=item * summary => STR

Used when displaying help message or version.

=item * module => STR

Currently this must be supplied if you want --version to work, even if you use
subcommands. --version gets $VERSION from the main module. Not required if you
specify 'spec'.

=item * sub => STR

Required if you only want to execute one subroutine. Alternatively you can
provide multiple subroutines from which the user can choose (see 'subcommands').

=item * spec => HASH | CODEREF

Instead of trying to look for the spec using B<module> and B<sub>, use the
supplied spec.

=item * help => STRING | CODEREF

Instead of generating help using gen_usage() from the spec, use the supplied
help message (or help code, which is expected to return help text).

=item * subcommands => {NAME => {ARGUMENT=>...}, ...} | CODEREF

B<module> and B<sub> should be specified if you only have one sub to run. If you
have several subs to run, assign each of them to a subcommand, e.g.:

 summary     => 'Maintain a directory containing git repos',
 module      => 'Git::Bunch',
 subcommands => {
   check   => { },
   backup  => { }, # module defaults to main module argument,
   sync    => { }, # sub defaults to the same name as subcommand name
 },

Available argument for each subcommand: 'module' (defaults to main B<module>
argument), 'sub' (defaults to subcommand name), 'summary', 'help', 'category'
(for arrangement when listing commands), 'run', 'complete_arg', 'complete_args'.

Subcommand argument can be a code reference, in which case it will be called
with C<%args> containing: 'name' (subcommand name), 'args' (arguments to run()).
The code is expected to return structure for argument with specified name, or,
when name is not specified, a hashref containing all subcommand arguments.

=item * run => CODEREF

Instead of running command by invoking subroutine specified by B<module> and
B<sub>, run this code instead. Code is expected to return a response structure
([CODE, MESSAGE, DATA]).

=item * exit => BOOL (default 1)

If set to 0, instead of exiting with exit(), return the exit code instead.

=item * load => BOOL (default 1)

If set to 0, do not try to load (require()) the module.

=item * allow_unknown_args => BOOL (default 0)

If set to 1, unknown command-line argument will not result in fatal error.

=item * complete_arg => {ARGNAME => CODEREF, ...}

Under bash completion, when completing argument value, you can supply a code to
provide its completion. Code will be called with %args containing: word, words,
arg, args.

=item * complete_args => CODEREF

Under bash completion, when completing argument value, you can supply a code to
provide its completion. Code will be called with %args containing: word, words,
arg, args.

=item * custom_completer => CODEREF

To be passed to L<Sub::Spec::BashComplete>'s bash_complete_spec_arg(). This can
be used e.g. to change bash completion code (e.g. calling
bash_complete_spec_arg() recursively) based on context.

=item * dash_to_underscore => BOOL (optional, default 0)

If set to 1, subcommand like a-b-c will be converted to a_b_c. This is for
convenience when typing in command line.

=back

run() can also perform completion for bash (if Sub::Spec::BashComplete is
available). To get bash completion for your B<perlprog>, just type this in bash:

 % complete -C /path/to/perlprog perlprog

You can add that line in bash startup file (~/.bashrc, /etc/bash.bashrc, etc).

=head1 FAQ

=head2 Why is nonscalar arguments parsed as YAML instead of JSON/etc?

I think YAML is nicer in command-line because quotes are optional in a few
places:

 $ cmd --array '[a, b, c]' --hash '{foo: bar}'

versus:

 $ cmd --array '["a", "b", "c"]' --hash '{"foo": "bar"}'

Though YAML requires spaces in some places where JSON does not. A flag to parse
as JSON can be added upon request.

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

