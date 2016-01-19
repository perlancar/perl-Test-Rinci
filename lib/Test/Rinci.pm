package Test::Rinci;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use experimental 'smartmatch';
#use Log::Any '$log';

use File::Spec;
use Perinci::Access::Perl 0.55;
#use SHARYANTO::Array::Util qw(match_array_or_regex); # we'll just use ~~
use Test::Builder;
use Test::More ();

my $Test = Test::Builder->new;
# XXX is cache_size=0 really necessary?
my $Pa = Perinci::Access::Perl->new(load=>0, cache_size=>0);

sub import {
    my $self = shift;
    my $caller = caller;
    no strict 'refs';
    *{$caller.'::metadata_in_module_ok'}      = \&metadata_in_module_ok;
    *{$caller.'::metadata_in_all_modules_ok'} = \&metadata_in_all_modules_ok;

    $Test->exported_to($caller);
    $Test->plan(@_);
}

sub _test_package_metadata {
    my ($uri, $opts) = @_;
    # XXX validate metadata
    $Test->ok(1, "currently no test for package metadata");
}

sub _test_function_metadata {
    my ($uri, $opts) = @_;
    my $ok = 1;

    # XXX validate metadata

    my $res = $Pa->request(meta => $uri);
    $Test->is_num($res->[0], 200, "wrap (load meta)") or $ok = 0;
    if ($res->[0] != 200) {
        $Test->diag("Can't meta $uri: $res->[0] - $res->[1]");
        return 0;
    }
    my $meta = $res->[2];
    if ($opts->{test_function_examples} && $meta->{examples}) {
        my $i = 0;
        for my $eg (@{ $meta->{examples} }) {
            $i++;
            next unless $eg->{test} // 1;
            $Test->subtest(
                "example #$i" . ($eg->{summary} ? " ($eg->{summary})" : ""),
                sub {
                    my $args;
                    if ($eg->{args}) {
                        $args = $eg->{args};
                    } elsif ($eg->{argv}) {
                        require Perinci::Sub::GetArgs::Argv;
                        my $r = Perinci::Sub::GetArgs::Argv::get_args_from_argv(
                            argv => $eg->{argv}, meta => $meta,
                        );
                        unless ($r->[0] == 200) {
                            $Test->diag("Can't parse argv into args");
                            $ok = 0;
                            return;
                        }
                        $args = $r->[2];
                    } elsif (defined $eg->{src}) {
                        $Test->diag("Skipping example #$i for now (src)");
                        Test::More::ok(1);
                        return;
                    } else {
                        $Test->diag("Bad example #$i: No args/argv/src");
                        $ok = 0;
                        return;
                    }
                    my $r = $Pa->request(call => $uri, {args=>$args});
                    $Test->is_num($r->[0], $eg->{status} // 200, "status")
                        or do { $Test->diag($Test->explain($r)); $ok = 0 };
                    if (exists $eg->{result}) {
                        Test::More::is_deeply($r, $eg->{result}, "result")
                              or do {
                                  Test::More::diag(
                                      Test::More::explain($r));
                                  $ok = 0;
                              };
                    }
                }) or $ok = 0;
        }
    }
    $ok;
}

sub _test_variable_metadata {
    my ($uri, $opts) = @_;
    # XXX validate metadata
    $Test->ok(1, "currently no test for variable metadata");
}

sub metadata_in_module_ok {
    my $module = shift;
    my %opts   = (@_ && (ref $_[0] eq "HASH")) ? %{(shift)} : ();
    my $msg    = @_ ? shift : "Rinci metadata on $module";
    my $res;
    my $ok = 1;

    $opts{test_package_metadata}   //= 1;
    $opts{exclude_packages}        //= [];
    $opts{test_function_metadata}  //= 1;
    $opts{wrap_function}           //= 1;
    $opts{test_function_examples}  //= 1;
    $opts{exclude_functions}       //= [];
    $opts{test_variable_metadata}  //= 1;
    $opts{exclude_variables}       //= [];

    my $has_tests;

    my $modulep = $module; $modulep =~ s!::!/!g; $modulep .= ".pm";
    require $modulep;

    $Test->subtest(
        $msg,
        sub {
            my $uri = "pl:/$module/"; $uri =~ s!::!/!g;

            if ($opts{test_package_metadata} &&
                    !($module ~~ $opts{exclude_packages})) {
                $res = $Pa->request(meta => $uri);
                if ($res->[0] != 200) {
                    $Test->ok(0, "load package metadata") or $ok = 0;
                    $Test->diag("Can't meta => $uri: $res->[0] - $res->[1]");
                    return 0;
                }
                $has_tests++;
                $Test->subtest(
                    "package metadata $module", sub {
                        _test_package_metadata($uri, \%opts);
                    }) or $ok = 0;
            } else {
                $Test->diag("Skipped testing package metadata $module");
            }

            return unless $opts{test_function_metadata} ||
                $opts{test_variable_metadata};

            $res = $Pa->request(list => $uri, {detail=>1});
            $Test->ok($res->[0] == 200, "list entities") or $ok = 0;
            if ($res->[0] != 200) {
                $Test->diag("Can't list => $uri: $res->[0] - $res->[1]");
                return 0;
            }
            for my $e (@{$res->[2]}) {
                my $en = $e->{uri};
                my $fen = "$en (in package $module)";
                if ($e->{type} eq 'function') {
                    if ($opts{test_function_metadata} &&
                            !($en ~~ $opts{exclude_functions})) {
                        $has_tests++;
                        $Test->subtest(
                            "function metadata $fen", sub {
                                _test_function_metadata("$uri$e->{uri}",
                                                        \%opts);
                            }) or $ok = 0;
                    } else {
                        $Test->diag("Skipped function metadata $fen");
                    }
                } elsif ($e->{type} eq 'variable') {
                    if ($opts{test_variable_metadata} &&
                            !($en ~~ $opts{exclude_variables})) {
                        $has_tests++;
                        $Test->subtest(
                            "variable metadata $fen", sub {
                                _test_variable_metadata("$uri$e->{uri}",
                                                        \%opts);
                            }) or $ok = 0;
                    } else {
                        $Test->diag("Skipped variable metadata $fen");
                    }
                } else {
                    $Test->diag("Skipped $e->{type} metadata $fen")
                        unless $e->{type} eq 'package';
                    next;
                }
            } # for list entry
        } # subtest
    ) or $ok = 0;

    unless ($has_tests) {
        $Test->ok(1);
        $Test->diag("No metadata to test");
    }

    $ok;
}

# BEGIN copy-pasted from Test::Pod::Coverage, with a bit modification

sub all_modules {
    my @starters = @_ ? @_ : _starting_points();
    my %starters = map {$_,1} @starters;

    my @queue = @starters;

    my @modules;
    while ( @queue ) {
        my $file = shift @queue;
        if ( -d $file ) {
            local *DH;
            opendir DH, $file or next;
            my @newfiles = readdir DH;
            closedir DH;

            @newfiles = File::Spec->no_upwards( @newfiles );
            @newfiles = grep { $_ ne "CVS" && $_ ne ".svn" } @newfiles;

            push @queue, map "$file/$_", @newfiles;
        }
        if ( -f $file ) {
            next unless $file =~ /\.pm$/;

            my @parts = File::Spec->splitdir( $file );
            shift @parts if @parts && exists $starters{$parts[0]};
            shift @parts if @parts && $parts[0] eq "lib";
            $parts[-1] =~ s/\.pm$// if @parts;

            # Untaint the parts
            for ( @parts ) {
                if ( /^([a-zA-Z0-9_\.\-]*)$/ && ($_ eq $1) ) {
                    $_ = $1;  # Untaint the original
                }
                else {
                    die qq{Invalid and untaintable filename "$file"!};
                }
            }
            my $module = join( "::", grep {length} @parts );
            push( @modules, $module );
        }
    } # while

    return @modules;
}

sub _starting_points {
    return 'blib' if -e 'blib';
    return 'lib';
}

# END copy-pasted from Test::Pod::Coverage

sub metadata_in_all_modules_ok {
    my $opts = (@_ && (ref $_[0] eq "HASH")) ? shift : {};
    my $msg  = shift;
    my $ok = 1;

    my @starters = _starting_points();
    local @INC = (@starters, @INC);

    $Test->plan(tests => 1);

    my @modules = all_modules(@starters);
    if (@modules) {
        $Test->subtest(
            "Rinci metadata on all dist's modules",
            sub {
                for my $module (@modules) {
                    #$log->infof("Processing module %s ...", $module);
                    my $thismsg = defined $msg ? $msg :
                        "Rinci metadata on $module";
                    my $thisok = metadata_in_module_ok(
                        $module, $opts, $thismsg)
                        or $ok = 0;
                }
            }
        ) or $ok = 0;
    } else {
        $Test->ok(1, "No modules found.");
    }
    $ok;
}

1;
# ABSTRACT: Test Rinci metadata

=for Pod::Coverage ^(all_modules)$

=head1 SYNOPSIS

To check all metadata in a module:

 use Test::Rinci tests=>1;
 metadata_in_module_ok("Foo::Bar", {opt => ...}, $msg);

Alternatively, you can check all metadata in all modules in a distro:

 # save in release-rinci.t, put in distro's t/ subdirectory
 use Test::More;
 plan skip_all => "Not release testing" unless $ENV{RELEASE_TESTING};
 eval "use Test::Rinci";
 plan skip_all => "Test::Rinci required for testing Rinci metadata" if $@;
 metadata_in_all_modules_ok({opt => ...}, $msg);


=head1 DESCRIPTION

This module performs various checks on a module's L<Rinci> metadata. It is
recommended that you include something like C<release-rinci.t> in your
distribution if you add metadata to your code. If you use L<Dist::Zilla> to
build your distribution, there is L<Dist::Zilla::Plugin::Test::Rinci> to make it
easy to do so.


=head1 FUNCTIONS

All these functions are exported by default.

=head2 metadata_in_module_ok($module [, \%opts ] [, $msg])

Load C<$module>, get its metadata, and perform test on all of them. For function
metadata, a wrapping to the function is done to see if it can be wrapped.

Available options:

=over 4

=item * test_package_metadata => BOOL (default: 1)

Whether to test package metadata found in module.

=item * exclude_packages => REGEX/ARRAY

List of packages to exclude from testing.

=item * test_function_metadata => BOOL (default: 1)

Whether to test function metadata found in module. Currently require
C<wrap_function> option to be turned on, as the tests are done to the metadata
generated by the wrapper (for convenience, since the wrapper can convert old
v1.0 metadata to v1.1).

=item * wrap_function => BOOL (default: 1)

Whether to wrap function (using L<Perinci::Sub::Wrapper>). All tests which run
module's functions require this option to be turned on.

=item * test_function_examples => BOOL (default: 1)

Whether to test examples in function metadata, by running each example and
comparing the specified result with actual result. Will only take effect when
C<test_function_metadata> and C<wrap_functions> is turned on.

=item * exclude_functions => REGEX/ARRAY

List of functions to exclude from testing.

=item * test_variable_metadata => BOOL (default: 1)

Whether to test function metadata found in module.

=item * exclude_variables => REGEX/ARRAY

List of variables to exclude from testing.

=back

=head2 metadata_in_all_modules_ok([ \%opts ] [, $msg])

Look for modules in directory C<lib> (or C<blib> instead, if it exists), and
C<run metadata_in_module_ok()> on each of them.

Options are the same as in C<metadata_in_module_ok()>.


=head1 ACKNOWLEDGEMENTS

Some code taken from L<Test::Pod::Coverage> by Andy Lester.


=head1 SEE ALSO

L<test-rinci>, a command-line interface for C<metadata_in_all_modules_ok()>.

L<Rinci>

L<Perinci::Sub::Wrapper>

L<Dist::Zilla::Plugin::Test::Rinci>

=cut
