#!/usr/bin/env perl

#### Copyright 2017 Henrik Stranneheim

use Modern::Perl qw{2014};
use warnings qw{FATAL utf8};
use autodie;
use 5.026;    #Require at least perl 5.18
use utf8;
use open qw{ :encoding(UTF-8) :std };
use charnames qw{ :full :short };
use Carp;
use English qw{-no_match_vars};
use Params::Check qw{check allow last_error};

use FindBin qw{$Bin};    #Find directory of script
use File::Basename qw{dirname basename};
use File::Spec::Functions qw{catdir};
use Getopt::Long;
use Test::More;
use FileHandle;
use Readonly;

## MIPs lib/
use lib catdir( dirname($Bin), 'lib' );
use MIP::Script::Utils qw{help};

## Constants
Readonly my $SPACE   => q{ };
Readonly my $NEWLINE => qq{\n};

our $USAGE = build_usage( {} );

my $VERBOSE = 1;
our $VERSION = '1.0.0';

###User Options
GetOptions(
    'h|help' => sub {
        done_testing();
        say {*STDOUT} $USAGE;
        exit;
    },    #Display help text
    'v|version' => sub {
        done_testing();
        say {*STDOUT} basename($PROGRAM_NAME) . $SPACE . $VERSION, $NEWLINE;

        exit;
    },    #Display version number
    'vb|verbose' => $VERBOSE,
  )
  or (
    done_testing(),
    help(
        {
            USAGE     => $USAGE,
            exit_code => 1,
        }
    )
  );

BEGIN {

### Check all internal dependency modules and imports
## Modules with import

    my %perl_module;

    $perl_module{'MIP::Script::Utils'} = [qw{help}];

  PERL_MODULES:
    while ( my ( $module, $module_import ) = each %perl_module ) {

        use_ok( $module, @{$module_import} )
          or BAIL_OUT 'Cannot load ' . $module;
    }

## Modules
    my @modules = ('MIP::Program::Alignment::Sambamba');

  MODULES:
    for my $module (@modules) {

        require_ok($module) or BAIL_OUT 'Cannot load ' . $module;
    }
}

use MIP::Program::Alignment::Sambamba qw{sambamba_markdup};
use MIP::Test::Commands qw{test_function};

diag(
"Test sambamba_markdup $MIP::Program::Alignment::Sambamba::VERSION, Perl $^V, $EXECUTABLE_NAME"
);

## Base arguments
my @function_base_commands = qw{ sambamba };

my %base_argument = (
    FILEHANDLE => {
        input           => undef,
        expected_output => \@function_base_commands,
    },
);

## Can be duplicated with %base and/or %specific to enable testing of each individual argument
my %required_argument = (
    FILEHANDLE => {
        input           => undef,
        expected_output => \@function_base_commands,
    },
    infile_path => {
        input           => q{infile.test},
        expected_output => q{infile.test},
    },
);

## Specific arguments
my %specific_argument = (
    stderrfile_path => {
        input           => q{stderrfile.test},
        expected_output => q{2> stderrfile.test},
    },
    temp_directory => {
        input           => q{temp},
        expected_output => q{--tmpdir=temp},
    },
    stdoutfile_path => {
        input           => q{outfile_path},
        expected_output => q{1> outfile_path},
    },
    hash_table_size => {
        input           => q{8},
        expected_output => q{--hash-table-size=8},
    },
    overflow_list_size => {
        input           => q{8},
        expected_output => q{--overflow-list-size=8},
    },
    io_buffer_size => {
        input           => q{16},
        expected_output => q{--io-buffer-size=16},
    },
    show_progress => {
        input           => 1,
        expected_output => q{--show-progress},
    },
    stderrfile_path_append => {
        input           => q{stderrfile_path_append},
        expected_output => q{2>> stderrfile_path_append},
    },
);

## Coderef - enables generalized use of generate call
my $module_function_cref = \&sambamba_markdup;

## Test both base and function specific arguments
my @arguments = ( \%base_argument, \%specific_argument );

foreach my $argument_href (@arguments) {

    my @commands = test_function(
        {
            argument_href              => $argument_href,
            required_argument_href     => \%required_argument,
            module_function_cref       => $module_function_cref,
            function_base_commands_ref => \@function_base_commands,
        }
    );
}

done_testing();

######################
####SubRoutines#######
######################

sub build_usage {

##build_usage

##Function : Build the USAGE instructions
##Returns  : ""
##Arguments: $program_name
##         : $program_name => Name of the script

    my ($arg_href) = @_;

    ## Default(s)
    my $program_name;

    my $tmpl = {
        program_name => {
            default     => basename($PROGRAM_NAME),
            strict_type => 1,
            store       => \$program_name,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak qw{Could not parse arguments!};

    return <<"END_USAGE";
 $program_name [options]
    -vb/--verbose Verbose
    -h/--help Display this help message
    -v/--version Display version
END_USAGE
}
