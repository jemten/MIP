package MIP::Language::Shell;

use strict;
use warnings;
use warnings qw(FATAL utf8);
use 5.018;    #Require at least perl 5.18
use utf8;     #Allow unicode characters in this script
use open qw( :encoding(UTF-8) :std );
use charnames qw( :full :short );
use Carp;
use English qw(-no_match_vars);
use Params::Check qw(check allow last_error);
$Params::Check::PRESERVE_CASE = 1;    #Do not convert to lower case

use Cwd;
use FindBin qw($Bin);                 #Find directory of script
use File::Basename qw(dirname basename);
use File::Spec::Functions qw(catfile catdir devnull);
use Readonly;

##MIPs lib/
use lib catdir( $Bin, 'lib' );        #Add MIPs internal lib

BEGIN {

    use base qw(Exporter);
    require Exporter;

    # Set the version for version checking
    our $VERSION = 1.02;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw(create_bash_file build_shebang
      create_housekeeping_function create_error_trap_function
      enable_trap clear_trap track_progress
    );
}

## Constants
Readonly my $SPACE => q{ };
Readonly my $COMMA => q{,};

sub create_bash_file {

##create_bash_file

##Function : Create bash file with header
##Returns  : ""
##Arguments: $file_name, $FILEHANDLE, $remove_dir, $log, $invoke_login_shell, $set_errexit, $set_nounset, $set_pipefail
##         : $file_name          => File name
##         : $FILEHANDLE         => Filehandle to write to
##         : $remove_dir         => Directory to remove when caught by trap function
##         : $log                => Log object to write to
##         : $invoke_login_shell => Invoked as a login shell. Reinitilize bashrc and bash_profile
##         : $set_errexit        => Halt script if command has non-zero exit code (-e)
##         : $set_nounset        => Halt script if variable is uninitialised (-u)
##         : $set_pipefail       => Detect errors within pipes (-o pipefail)

    my ($arg_href) = @_;

    ## Default(s)
    my $invoke_login_shell;
    my $set_errexit;
    my $set_nounset;
    my $set_pipefail;

    ## Flatten argument(s)
    my $file_name;
    my $FILEHANDLE;
    my $remove_dir;
    my $log;

    my $tmpl = {
        file_name => {
            required    => 1,
            defined     => 1,
            strict_type => 1,
            store       => \$file_name
        },
        FILEHANDLE => { required => 1, store => \$FILEHANDLE },
        log        => { store    => \$log },
        remove_dir => {
            allow       => qr/^\S+$/x,
            strict_type => 1,
            store       => \$remove_dir
        },
        invoke_login_shell => {
            default     => 0,
            allow       => [ 0, 1 ],
            strict_type => 1,
            store       => \$invoke_login_shell
        },
        set_errexit => {
            default     => 0,
            allow       => [ 0, 1 ],
            strict_type => 1,
            store       => \$set_errexit
        },
        set_nounset => {
            default     => 0,
            allow       => [ 0, 1 ],
            strict_type => 1,
            store       => \$set_nounset
        },
        set_pipefail => {
            default     => 0,
            allow       => [ 0, 1 ],
            strict_type => 1,
            store       => \$set_pipefail
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak qw[Could not parse arguments!];

    use MIP::Gnu::Bash qw(gnu_set);

    ## Build bash shebang line
    build_shebang(
        {
            FILEHANDLE         => $FILEHANDLE,
            invoke_login_shell => $invoke_login_shell,
        }
    );

    ## Set shell attributes
    gnu_set(
        {
            FILEHANDLE   => $FILEHANDLE,
            set_errexit  => $set_errexit,
            set_nounset  => $set_nounset,
            set_pipefail => $set_pipefail,
        }
    );

    ## Create housekeeping function which removes entire directory when finished
    create_housekeeping_function(
        {
            remove_dir         => $remove_dir,
            trap_function_name => 'finish',
            FILEHANDLE         => $FILEHANDLE,
        }
    );

    ## Create debug trap
    enable_trap(
        {
            FILEHANDLE         => $FILEHANDLE,
            trap_signals_ref   => ['DEBUG'],
            trap_function_call => q{previous_command="$BASH_COMMAND"},
        }
    );

    ## Create error handling function and trap
    create_error_trap_function( { FILEHANDLE => $FILEHANDLE, } );

    if ( ( defined $log ) && ($log) ) {

        $log->info( q{Created bash file: '} . catfile($file_name), q{'}, "\n" );
    }
    else {

        print {*STDERR} q{Created bash file: '} . catfile($file_name), q{'},
          "\n";
    }
    return;
}

sub build_shebang {

##build_shebang

##Function : Build bash shebang line. Returns "@commands" or writes to already opened filehandle.
##Returns  : "@commands"
##Arguments: $FILEHANDLE, $bash_bin_path, $invoke_login_shell, $separator
##         : $FILEHANDLE         => Filehandle to write to
##         : $bash_bin_path      => Location of bash bin
##         : $invoke_login_shell => Invoked as a login shell (-l). Reinitilize bashrc and bash_profile
##         : $separator          => Separator to use when writing

    my ($arg_href) = @_;

    ## Default(s)
    my $bash_bin_path;
    my $invoke_login_shell;
    my $separator;

    ## Flatten argument(s)
    my $FILEHANDLE;

    ## Constants
    my $NEWLINE = q{\n};

    my $tmpl = {
        FILEHANDLE    => { store => \$FILEHANDLE },
        bash_bin_path => {
            default =>
              catfile( dirname( dirname( devnull() ) ), qw(usr bin env bash) ),
            allow       => qr/^\S+$/,
            strict_type => 1,
            store       => \$bash_bin_path
        },
        invoke_login_shell => {
            default     => 0,
            allow       => [ 0, 1 ],
            strict_type => 1,
            store       => \$invoke_login_shell
        },
        separator => {
            default     => $NEWLINE,
            strict_type => 1,
            store       => \$separator
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak qw(Could not parse arguments!);

    use MIP::Unix::Write_to_file qw(unix_write_to_file);

    ## Build shebang
    my @commands =
      ( q{#!} . $bash_bin_path ); #Stores commands depending on input parameters

    ##Invoke as login shell
    if ($invoke_login_shell) {

        $commands[0] .= q{ --login};
    }

    unix_write_to_file(
        {
            commands_ref => \@commands,
            separator    => $separator,
            FILEHANDLE   => $FILEHANDLE,
        }
    );
    return @commands;
}

sub create_housekeeping_function {

##create_housekeeping_function

##Function : Create housekeeping function which removes entire directory when finished
##Returns  : ""
##Arguments: $job_ids_ref, $sacct_format_fields_ref, $log_file_path_ref, $FILEHANDLE, $remove_dir, $trap_function_call, $trap_signals_ref, $trap_function_name
##         : $job_ids_ref             => Job ids
##         : $sacct_format_fields_ref => Format and fields of sacct output
##         : $log_file_path_ref       => Log file to write job_id progress to {REF}
##         : $FILEHANDLE              => Filehandle to write to
##         : $remove_dir              => Directory to remove when caught by trap function
##         : $trap_function_call      => Trap function call
##         : $trap_signals_ref        => Array with signals to enable trap for {REF}
##         : $trap_function_name      => The trap function argument

    my ($arg_href) = @_;

    ## Default(s)
    my $trap_signals_ref;
    my $trap_function_name;
    my $trap_function_call;

    ## Flatten argument(s)
    my $job_ids_ref;
    my $sacct_format_fields_ref;
    my $log_file_path_ref;
    my $FILEHANDLE;
    my $remove_dir;

    my $tmpl = {
        job_ids_ref =>
          { default => [], strict_type => 1, store => \$job_ids_ref },
        sacct_format_fields_ref => {
            default     => [],
            strict_type => 1,
            store       => \$sacct_format_fields_ref
        },
        log_file_path_ref =>
          { default => \$$, strict_type => 1, store => \$log_file_path_ref },
        FILEHANDLE         => { required    => 1, store => \$FILEHANDLE },
        remove_dir         => { strict_type => 1, store => \$remove_dir },
        trap_function_call => {
            default => q{$(}
              . $arg_href->{trap_function_name}
              . $SPACE
              . $arg_href->{remove_dir} . q{)},
            strict_type => 1,
            store       => \$trap_function_call
        },
        trap_signals_ref => {
            default     => [qw(EXIT TERM INT)],
            strict_type => 1,
            store       => \$trap_signals_ref
        },
        trap_function_name => {
            default     => 'finish',
            strict_type => 1,
            store       => \$trap_function_name
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak qw[Could not parse arguments!];

    use MIP::Gnu::Coreutils qw(gnu_rm);

    ## Create housekeeping function and trap
    say {$FILEHANDLE} $trap_function_name . q?() {?, "\n";

    if ( ( defined $remove_dir ) && ($remove_dir) ) {

        say   {$FILEHANDLE} "\t" . q{local directory="$1"};
        say   {$FILEHANDLE} "\t" . q{## Perform exit housekeeping};
        print {$FILEHANDLE} "\t";

        gnu_rm(
            {
                infile_path => q{"$directory"},
                force       => 1,
                recursive   => 1,
                FILEHANDLE  => $FILEHANDLE,
            }
        );
        say {$FILEHANDLE} "\n";
    }
    if (   ( defined $job_ids_ref )
        && ( @{$job_ids_ref} )
        && ( defined ${$log_file_path_ref} )
        && ( ${$log_file_path_ref} ) )
    {

        ## Output SLURM info on each job via sacct command
        ## and write to log file(.status)
        track_progress(
            {
                job_ids_ref             => \@{$job_ids_ref},
                sacct_format_fields_ref => \@{$sacct_format_fields_ref},
                FILEHANDLE              => $FILEHANDLE,
                log_file_path_ref       => $log_file_path_ref,
            }
        );
    }

    say {$FILEHANDLE} q?}?;

    ## Enable trap function with trap signal(s)
    enable_trap(
        {
            FILEHANDLE         => $FILEHANDLE,
            trap_signals_ref   => \@{$trap_signals_ref},
            trap_function_call => $trap_function_call,
        }
    );
    return;
}

sub create_error_trap_function {

##create_error_trap_function

##Function : Create error handling function and trap
##Returns  : ""
##Arguments: $job_ids_ref, sacct_format_fields_ref, $log_file_path_ref, $FILEHANDLE, $trap_function_call, $trap_signals_ref, $trap_function_name
##         : $job_ids_ref             => Job ids
##         : $sacct_format_fields_ref => Format and fields of sacct output
##         : $log_file_path_ref       => Log file to write job_id progress to {REF}
##         : $FILEHANDLE              => Filehandle to write to
##         : $trap_function_call      => Trap function call
##         : $trap_signals_ref        => Array with signals to enable trap for {REF}
##         : $trap_function_name      => The trap function argument

    my ($arg_href) = @_;

    ## Default(s)
    my $trap_signals_ref;
    my $trap_function_name;

    ## Flatten argument(s)
    my $job_ids_ref;
    my $sacct_format_fields_ref;
    my $log_file_path_ref;
    my $FILEHANDLE;
    my $trap_function_call;

    my $tmpl = {
        job_ids_ref =>
          { default => [], strict_type => 1, store => \$job_ids_ref },
        sacct_format_fields_ref => {
            default     => [],
            strict_type => 1,
            store       => \$sacct_format_fields_ref
        },
        log_file_path_ref =>
          { default => \$$, strict_type => 1, store => \$log_file_path_ref },
        FILEHANDLE         => { required => 1, store => \$FILEHANDLE },
        trap_function_call => {
            default     => q{$(error "$previous_command" "$?")},
            strict_type => 1,
            store       => \$trap_function_call
        },
        trap_signals_ref => {
            default     => ['ERR'],
            strict_type => 1,
            store       => \$trap_signals_ref
        },
        trap_function_name => {
            default     => 'error',
            strict_type => 1,
            store       => \$trap_function_name
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak qw[Could not parse arguments!];

    ## Create error handling function and trap
    say {$FILEHANDLE} $trap_function_name . q?() {?, "\n";
    say {$FILEHANDLE} "\t" . q{local program="$1"},     "\n";
    say {$FILEHANDLE} "\t" . q{local return_code="$2"}, "\n";

    if (   ( defined $job_ids_ref )
        && ( @{$job_ids_ref} )
        && ( defined ${$log_file_path_ref} )
        && ( ${$log_file_path_ref} ) )
    {

        ## Output SLURM info on each job via sacct command
        ## and write to log file(.status)
        track_progress(
            {
                job_ids_ref             => \@{$job_ids_ref},
                sacct_format_fields_ref => \@{$sacct_format_fields_ref},
                FILEHANDLE              => $FILEHANDLE,
                log_file_path_ref       => $log_file_path_ref,
            }
        );
    }

    say {$FILEHANDLE} "\t" . q{## Display error message and exit};
    say {$FILEHANDLE} "\t"
      . q?echo "${program}: ${return_code}: Unknown Error - ExitCode=$return_code" 1>&2?;
    say {$FILEHANDLE} "\t" . q{exit 1};
    say {$FILEHANDLE} q?}?;

    ## Enable trap function with trap signal(s)
    enable_trap(
        {
            FILEHANDLE         => $FILEHANDLE,
            trap_signals_ref   => \@{$trap_signals_ref},
            trap_function_call => $trap_function_call,
        }
    );
    return;
}

sub clear_trap {

##clear_trap

##Function : Clear trap for signal(s), e.g. in exome analysis since the might be no variants in MT or Y contigs. This will cause premature exit from sbatch
##Returns  : ""
##Arguments: $FILEHANDLE, $trap_signals_ref
##         : $FILEHANDLE       => The FILEHANDLE to write to
##         : $trap_signals_ref => Array with signals to clear trap for {REF}

    my ($arg_href) = @_;

    ## Default(s)
    my $trap_signals_ref;

    ## Flatten argument(s)
    my $FILEHANDLE;

    my $tmpl = {
        FILEHANDLE       => { required => 1, store => \$FILEHANDLE },
        trap_signals_ref => {
            default     => ['ERR'],
            strict_type => 1,
            store       => \$trap_signals_ref
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak(qw[Could not parse arguments!]);

    use MIP::Gnu::Bash qw(gnu_trap);

    ## Clear trap for signal ERR
    print {$FILEHANDLE} "\n## Clear trap for signal(s) "
      . join( $SPACE, @{$trap_signals_ref} ), "\n";

    gnu_trap(
        {
            trap_signals_ref   => $trap_signals_ref,
            trap_function_call => '-',
            FILEHANDLE         => $FILEHANDLE,
        }
    );
    gnu_trap( { FILEHANDLE => $FILEHANDLE, } );
    say {$FILEHANDLE} "\n";
    return;
}

sub enable_trap {

##enable_trap

##Function : Enable trap function with trap signal(s).
##Returns  : ""
##Arguments: $FILEHANDLE, $trap_signals_ref, $trap_function_call
##         : $FILEHANDLE         => The FILEHANDLE to write to
##         : $trap_signals_ref   => Array with signals to enable trap for {REF}
##         : $trap_function_call => The trap function argument

    my ($arg_href) = @_;

    ## Default(s)
    my $trap_signals_ref;
    my $trap_function_call;

    ## Flatten argument(s)
    my $FILEHANDLE;

    my $tmpl = {
        FILEHANDLE       => { required => 1, store => \$FILEHANDLE },
        trap_signals_ref => {
            default     => ['ERR'],
            strict_type => 1,
            store       => \$trap_signals_ref
        },
        trap_function_call => {
            default     => 'error',
            strict_type => 1,
            store       => \$trap_function_call
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak qw[Could not parse arguments!];

    use MIP::Gnu::Bash qw(gnu_trap);

    print {$FILEHANDLE} "\n## Enable trap for signal(s) "
      . join( $SPACE, @{$trap_signals_ref} ), "\n";

    gnu_trap(
        {
            trap_signals_ref   => $trap_signals_ref,
            trap_function_call => $trap_function_call,
            FILEHANDLE         => $FILEHANDLE,
        }
    );
    say {$FILEHANDLE} "\n";
    return;
}

sub track_progress {

##track_progress

##Function : Output SLURM info on each job via sacct command and write to log file(.status)
##Returns  : ""
##Arguments: $job_ids_ref, $sacct_format_fields_ref, $log_file_path_ref, $FILEHANDLE
##         : $job_ids_ref             => Job ids
##         : $sacct_format_fields_ref => Format and fields of sacct output
##         : $log_file_path_ref       => The log file {REF}
##         : $FILEHANDLE              => Sbatch filehandle to write to

    my ($arg_href) = @_;

    ## Default(s)
    my $sacct_format_fields_ref;

    ## Flatten argument(s)
    my $job_ids_ref;
    my $log_file_path_ref;
    my $FILEHANDLE;

    my $tmpl = {
        job_ids_ref =>
          { default => [], strict_type => 1, store => \$job_ids_ref },
        sacct_format_fields_ref => {
            default => [
                'jobid',     'jobname%50', 'account', 'partition',
                'alloccpus', 'TotalCPU',   'elapsed', 'start',
                'end',       'state',      'exitcode'
            ],
            strict_type => 1,
            store       => \$sacct_format_fields_ref
        },
        log_file_path_ref =>
          { default => \$$, strict_type => 1, store => \$log_file_path_ref },
        FILEHANDLE => { store => \$FILEHANDLE },
    };

    check( $tmpl, $arg_href, 1 ) or croak qw[Could not parse arguments!];

    use MIP::Workloadmanager::Slurm qw(slurm_sacct slurm_reformat_sacct_output);

    if ( @{$job_ids_ref} ) {

        ## Copy array
        my @reformat_sacct_headers = @{$sacct_format_fields_ref};

        ## Remove "%digits" from headers
        foreach my $element (@reformat_sacct_headers) {

            $element =~ s/%\d+//g;
        }
        my @commands = slurm_sacct(
            {
                fields_format_ref => \@{$sacct_format_fields_ref},
                job_ids_ref       => \@{$job_ids_ref},
            }
        );

        slurm_reformat_sacct_output(
            {
                commands_ref               => \@commands,
                reformat_sacct_headers_ref => \@reformat_sacct_headers,
                log_file_path_ref          => $log_file_path_ref,
                FILEHANDLE                 => $FILEHANDLE,
            }
        );
    }
    return;
}

1;