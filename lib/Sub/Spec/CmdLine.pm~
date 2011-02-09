package Sub::Spec::CmdLine;
# ABSTRACT: Access Perl subs via command line

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

use Getopt::Long    qw(GetOptionsFromArray);

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
    require YAML::Syck; $YAML::Syck::ImplicitTyping = 1;

    my ($argv, $sub_spec) = @_;
    my $spec_args         = $sub_spec->{args}          // {};
    my $spec_req_args     = $sub_spec->{required_args} // [];

    $spec_args = { map { $_ => _parse_schema($spec_args->{$_}) }
                       keys %$spec_args };

    my %go_spec;

    my $args = {};
    while (my ($name, $schema) = each %$spec_args) {
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
    my $result = GetOptionsFromArray($argv, %go_spec);
    die "Incorrect command-line options/arguments\n" unless $result;

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

    # process arg_order
  ARGV:
    for my $i (reverse 0..@$argv-1) {
        while (my ($name, $schema) = each %$spec_args) {
            my $ah0 = $schema->{attr_hashes}[0];
            my $o = $ah0->{arg_order};
            if (defined($o) && $o == $i) {
                die "You specified option --$name but also argument #".
                    ($i+1)."\n" if defined($args->{$name});
                if ($ah0->{arg_greedy}) {
                    $args->{$name} = [splice(@$argv, $i)];
                    last ARGV;
                } else {
                    $args->{$name} = splice(@$argv, $i, 1);
                }
            }
        }
    }

    $log->tracef("tmp args result (after arg_order processing): %s, argv: %s",
                 $args, $argv);
    die "Error: extra argument(s): ".join(", ", @$argv)."\n" if @$argv;

    # check required args
    for (@$spec_req_args) {
        die "Missing required argument: $_\n" unless defined $args->{$_};
        # should really be exists() instead of defined(), but doesn't work well
        # yet
    }

    # XXX should not really be done, at some time we might need to differentiate
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

    if ($sub_spec->{summary}) {
        $usage .= ($sub_spec->{_module} ? "$sub_spec->{_module}::" : "") .
            ($sub_spec->{_sub} ? "$sub_spec->{_sub} - " : "") .
                "$sub_spec->{summary}\n\n";
    }

    my $desc = $sub_spec->{description};
    if ($desc) {
        $desc =~ s/^\n+//; $desc =~ s/\n+$//;
        $usage .= "$desc\n\n";
    }

    my $args  = $sub_spec->{args} // {};
    my $rargs = $sub_spec->{required_args};
    $args = { map {$_ => _parse_schema($args->{$_})} keys %$args };
    my $prev_cat;
    for my $name (sort {
        (($args->{$a}{attr_hashes}[0]{arg_category} // "") cmp
             ($args->{$b}{attr_hashes}[0]{arg_category} // "")) ||
                 (($args->{$a}{attr_hashes}[0]{arg_order} // 9999) <=>
                      ($args->{$b}{attr_hashes}[0]{arg_order} // 9999)) ||
                          ($a cmp $b) } keys %$args) {
        my $arg = $args->{$name};
        my $ah0 = $arg->{attr_hashes}[0];

        my $cat = $ah0->{arg_category} // "";
        if (!defined($prev_cat) || $prev_cat ne $cat) {
            $usage .= ($cat ? "$cat options" : "Options") .
                ": (* denotes required options):\n";
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

        my $o = $ah0->{arg_order};
        my $g = $ah0->{arg_greedy};

        $arg_desc .= " $ah0->{summary}" if $ah0->{summary};
        $arg_desc .= " (one of: ".
            Data::Dump::Partial::dumpp($ah0->{choices}).")"
                  if defined($ah0->{choices});
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
        $usage .= "Examples:\n\n";
        my $cmd = $opts->{cmd} // $0;
        for my $ex (@{ $sub_spec->{cmdline_examples} }) {
            $usage .= "% $cmd $ex->{cmd}\n";
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
        my $r;
        if ($res->[0] == 200) {
            $r = $res->[2];
            $r //= $opts->{default_success_message}
                if $opts->{default_success_message};
        } else {
            $r = defined($res->[2]) ? $res : "ERROR $res->[0]: $res->[1]";
        }
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
    my %args = @_;

    my %opts = (format => undef, action => 'run');
    Getopt::Long::Configure("pass_through");
    GetOptions(
        "--list|l"     => sub { $opts{action} = 'list'     },
        "--help|h|?"   => sub { $opts{action} = 'help'     },

        "--text"       => sub { $opts{format} = 'text'     },
        "--yaml"       => sub { $opts{format} = 'yaml'     },
        "--json"       => sub { $opts{format} = 'json'     },
        "--pretty"     => sub { $opts{format} = 'pretty'   },
        "--nopretty"   => sub { $opts{format} = 'nopretty' },
    );

    my $exit = $args{exit} // 1;
    my $subcmds = $args{subcommands};
    my $module;
    my $sub;

    # handle --list
    if ($opts{action} eq 'list') {
        if ($subcmds) {
            # XXX sort by category
            for my $c (sort keys %$subcmds) {
                my $sc = $subcmds->{$c};
                say "  $c", ($sc->{summary} ? " - $sc->{summary}" : "");
            }
        }
        if ($exit) { exit 0 } else { return 0 }
    }

    # finding out which module/sub to use
    my $subcmdname;
    my $subcmd;
    if ($args{subcommands}) {
        $subcmdname = shift @ARGV or die "Please specify a subcommand, ".
            "use $0 -l to list available subcommands\n";
        my $subcmd = $args{subcommands}{$subcmdname};
        $subcmd or die "Unknown subcommand `$subcmd`, please ".
            "use $0 -l to list available subcommands\n";
        $module = $subcmd->{module} // $args{module};
        $sub    = $subcmd->{sub}    // $subcmdname;
    } else {
        $module = $args{module};
        $sub    = $args{sub};
    }

    my $cmd = $args{cmd} // $0;

    # require module and get spec
    my $modulep = $args{module};
    $modulep =~ s!::!/!g; $modulep .= ".pm";
    if ($args{require} // 1) {
        eval { require $modulep };
        die $@ if $@;
    }
    no strict 'refs';
    my $subs = \%{$module."::SUBS"};
    my $spec = $subs->{$sub};
    die "Can't find spec for sub $module\::$sub\n" unless $spec;

    # handle general --help
    if ($opts{action} eq 'help') {
        if ($args{subcommands}) {
            say $cmd, ($args{summary} ? " - $args{summary}" : "");
            print <<_;

Usage:
  $cmd SUBCOMMAND [ARGS ...]
  $cmd SUBCOMMAND --help (or -l, or -?)
  $cmd --list (or -?)
  $cmd --help

Options:
  --list    List subcommands
  --help    Show this message
_
        } else {
            print gen_usage($spec, {cmd=>$cmd});
        }
        if ($exit) { exit 0 } else { return 0 }
    }

    # handle per-command --help
    if ($subcmd && $ARGV[0] =~ /^(--help|-h|-\?)$/) {
        print gen_usage($spec, {cmd=>"$cmd $subcmdname"});
        if ($exit) { exit 0 } else { return 0 }
    }

    my $args = parse_argv(\@ARGV, $spec);

    my $subref = \&{$module."::$sub"};
    my $res    = $subref->(%$args);

    $log->tracef("opts=%s", \%opts);
    print format_result($res, $opts{format});
    my $exit_code = $res->[0] == 200 ? 0 : $res->[0] - 300;
    if ($exit) { exit $exit_code } else { return $exit_code }
}

1;
__END__

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


=head2 parse_argv(\@argv, $sub_spec) => \%args

Parse command line argument @argv into hash %args, suitable for passing into
subs.

Uses Getopt::Long to parse the result. You can Getopt::Long::Configure
beforehand to modify behaviour (e.g. if you want no_permute).

Note: As with GetOptions, this function modifies its argument, @argv.

Why would one use this function instead of using Getopt::Long directly? We want
YAML parsing (ability to pass data structures via command line), parsing of
arg_order and arg_greedy, stricter behaviour (dies on error).

One problem with Getopt::Long: all options get set to undef even if not
specified. So currently we delete undef keys in %$args.

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

Run sub from the command line, which essentially comprises these
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

=item * subcommands => {NAME => {module=>..., sub=>..., summary=>...}, ...}

B<module> and B<sub> should be specified if you only have one sub to run. If you
have several subs to run, assign each of them to a subcommand, e.g.:

 summary     => 'Maintain a directory containing git repos',
 module      => 'Git::Bunch',
 subcommands => {
   backup  => { }, # module defaults to main module argument,
   status  => { }, # sub defaults to the same name as subcommand name
 },

=item * exit => BOOL (optional, default 1)

If set to 0, instead of exiting with exit(), return the exit code instead.

=item * require => BOOL (optional, default 1)

If set to 0, do not try to require the module.

=back

=head1 SEE ALSO

L<Sub::Spec>

L<Sub::Spec::Pod>

L<MooseX::Getopt>

=cut
