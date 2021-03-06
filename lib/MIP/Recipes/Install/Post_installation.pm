package MIP::Recipes::Install::Post_installation;

use 5.026;
use Carp;
use Cwd qw{ abs_path };
use English qw{ -no_match_vars };
use File::Basename qw{ fileparse };
use File::Spec::Functions qw{ catfile catdir };
use FindBin qw{ $Bin };
use List::Util qw{ any };
use Params::Check qw{ allow check last_error };
use charnames qw{ :full :short };
use open qw{ :encoding(UTF-8) :std };
use strict;
use Time::Piece;
use utf8;
use warnings qw{ FATAL utf8 };
use warnings;

## CPANM
use autodie qw{ :all };
use List::MoreUtils qw{ natatime };
use Readonly;

## MIPs lib/
use MIP::File::Format::Yaml qw{ load_yaml };
use MIP::Get::Parameter qw{ get_env_method_cmds };
use MIP::Gnu::Coreutils qw{ gnu_cp gnu_echo gnu_printf gnu_rm };
use MIP::Unix::Write_to_file qw{ unix_write_to_file };

BEGIN {
    require Exporter;
    use base qw{ Exporter };

    # Set the version for version checking
    our $VERSION = 1.00;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw{
      build_perl_program_check_command
      check_program_installations
      update_config
    };
}

## Constants
Readonly my $DOUBLE_QUOTE => q{"};
Readonly my $NEWLINE      => qq{\n};
Readonly my $SINGLE_QUOTE => q{'};
Readonly my $SPACE        => q{ };
Readonly my $TAB          => qq{\t};

sub check_program_installations {

## Function : Write installation check oneliner to open filehandle
## Returns  :
## Arguments: $env_name                   => Program environment name
##          : $FILEHANDLE                 => open filehandle
##          : $installation               => installation
##          : $log                        => Log
##          : $programs_ref               => Programs to check {REF}
##          : $program_test_command_href  => Hash with test commands {REF}

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $env_name;
    my $FILEHANDLE;
    my $installation;
    my $log;
    my $programs_ref;
    my $program_test_command_href;

    my $tmpl = {
        env_name => {
            defined     => 1,
            required    => 1,
            store       => \$env_name,
            strict_type => 1,
        },
        FILEHANDLE => {
            required => 1,
            store    => \$FILEHANDLE,
        },
        installation => {
            defined     => 1,
            required    => 1,
            store       => \$installation,
            strict_type => 1,
        },
        log => {
            required => 1,
            store    => \$log,
        },
        programs_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$programs_ref,
            strict_type => 1,
        },
        program_test_command_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$program_test_command_href,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    Readonly my $COLUMNS      => 4;
    Readonly my $COLUMN_WIDTH => 25;
    Readonly my $HASH_SIGN    => q{#};

    $log->info(qq{Writing tests for programs installed in environment: $env_name});

    ## Sort program list for readability
    my @sorted_programs = sort { lc $a cmp lc $b } @{$programs_ref};

    ## Get environment commands
    my @env_method_load_cmds = get_env_method_cmds(
        {
            action     => q{load},
            env_method => q{conda},
            env_name   => $env_name,
        }
    );

    my @env_method_unload_cmds = get_env_method_cmds(
        {
            action     => q{unload},
            env_method => q{conda},
            env_name   => $env_name,
        }
    );

    ## Construct perl test for programs
    my @perl_commands = build_perl_program_check_command(
        {
            programs_ref              => \@sorted_programs,
            program_test_command_href => $program_test_command_href,
        },
    );

    ## Return if there are no tests to be written;
    if ( not @perl_commands ) {
        $log->info(qq{No tests available for programs in environment: $env_name});
        return;
    }

    say {$FILEHANDLE} qq{## Testing programs installed in $env_name};

    ## Build header string to echo
    my @header = ( q{\n} . ( $HASH_SIGN x $COLUMN_WIDTH x $COLUMNS ) . q{\n\n} );
    push @header, (q{\tMIP has attempted to install the following programs\n});
    push @header, ( q{\tin environment: } . $env_name . q{\n\n} );

    gnu_echo(
        {
            enable_interpretation => 1,
            FILEHANDLE            => $FILEHANDLE,
            strings_ref           => \@header,
        }
    );
    say {$FILEHANDLE} $NEWLINE;

    ## Print programs selected for installation in sets
    my $program_iterator = natatime $COLUMNS, @sorted_programs;

    ## Create field layout for printf
    my $field = q{"\t} . ( ( q{%-} . $COLUMN_WIDTH . q{s} ) x $COLUMNS ) . q{\n"};

  PRINT_SET:
    while ( my @print_set = $program_iterator->() ) {
        ## Print programs according to field
        my $format_string =
            $field
          . $SPACE
          . $DOUBLE_QUOTE
          . join( $DOUBLE_QUOTE . $SPACE . $DOUBLE_QUOTE, @print_set )
          . $DOUBLE_QUOTE;
        gnu_printf(
            {
                FILEHANDLE    => $FILEHANDLE,
                format_string => $format_string,
            }
        );
        print {$FILEHANDLE} $NEWLINE;
    }

    gnu_echo(
        {
            enable_interpretation => 1,
            FILEHANDLE            => $FILEHANDLE,
            strings_ref           => [q{\n\tTesting installation\n}],
        }
    );
    say {$FILEHANDLE} $NEWLINE;

    ## Load env
    say   {$FILEHANDLE} qq{## Load environment: $env_name};
    say   {$FILEHANDLE} join $SPACE, @env_method_load_cmds;
    print {$FILEHANDLE} $NEWLINE;

    ## Create success and fail case
    my $installation_outcome = uc $installation;
    my $success_message =
      q{\n\tAll programs were succesfully installed in: } . $env_name . q{\n};
    my $fail_message =
      q{\n\tMIP failed to install some programs in: } . $env_name . q{\n};

    my $success_echo = join $SPACE,
      gnu_echo(
        {
            enable_interpretation => 1,
            strings_ref           => [$success_message],
        }
      );
    my $fail_echo = join $SPACE,
      gnu_echo(
        {
            enable_interpretation => 1,
            strings_ref           => [$fail_message],
        }
      );

    my $success_case = qq?&& { $success_echo; $installation_outcome=success; }?;
    my $fail_case    = qq?|| { $fail_echo; }?;

    ## Write test oneliner
    say {$FILEHANDLE} q{## Test programs and capture outcome in bash variable};
    print {$FILEHANDLE} join $SPACE, @perl_commands;
    say {$FILEHANDLE} $SPACE . $success_case . $SPACE . $fail_case . $NEWLINE;

    ## Unload env
    say   {$FILEHANDLE} qq{## Unload environment: $env_name};
    say   {$FILEHANDLE} join $SPACE, @env_method_unload_cmds;
    print {$FILEHANDLE} $NEWLINE;

    return;
}

sub update_config {

## Function : Write installation check oneliner to open filehandle
## Returns  :
## Arguments: $env_name_href      => Program environment name hash {REF}
##          : $FILEHANDLE         => open filehandle
##          : $installations_ref  => Array with installations {REF}
##          : $log                => Log
##          : $pipeline           => Pipeline
##          : $update_config      => Path to config to update
##          : $write_config       => Create new config from template

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $env_name_href;
    my $FILEHANDLE;
    my $installations_ref;
    my $log;
    my $pipeline;
    my $update_config;
    my $write_config;

    my $tmpl = {
        env_name_href => {
            defined     => 1,
            default     => {},
            required    => 1,
            store       => \$env_name_href,
            strict_type => 1,
        },
        FILEHANDLE => {
            required => 1,
            store    => \$FILEHANDLE,
        },
        installations_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$installations_ref,
            strict_type => 1,
        },
        log => {
            required => 1,
            store    => \$log,
        },
        pipeline => {
            defined     => 1,
            required    => 1,
            store       => \$pipeline,
            strict_type => 1,
        },
        update_config => {
            store       => \$update_config,
            strict_type => 1,
        },
        write_config => {
            store       => \$write_config,
            strict_type => 1,
        },

    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    ## Return if no config options
    return if ( not $update_config ) and ( not $write_config );

    ## map installation to bash paramter
    my %installation_outcome = map { $_ => q{$} . uc $_ } @{$installations_ref};

    ## Set config paths
    my $load_config_path;
    my $save_config_path;
    my $date_time  = localtime;
    my $time_stamp = $date_time->datetime;
    if ($update_config) {

        ## get absolute path
        $update_config = abs_path($update_config);

        ## Check that file exists
        if ( not -e $update_config ) {
            $log->warn(
q{MIP will not attempt to update config as the specified path does not exist.}
            );
            return;
        }

        ## Isolate filename
        my ( $filename, $dirs, $suffix ) = fileparse( $update_config, qr/\.y[a?]ml/xms );

        ## Match date format YYYY-MM... | YY-MM... | YYMMDD...
        my $date_regex = qr{
			(?:\d\d\d?\d?\d?\d?) # match YYYY | YY | YYMMDD
			-?                   # optionally match -
			(?:\d?\d?)           # optionally match MM 
			.*                   # match any remaining part
		}xms;

        ## Replace potential dates
        $filename =~ s/_$date_regex/_$time_stamp/xms;
        $load_config_path = $update_config;
        $save_config_path = catfile( $dirs, $filename . $suffix );
        $log->info( q{Writing instructions to update config: } . $save_config_path );
    }
    else {

        ## Copy template and add time stamp
        $load_config_path =
          catfile( $Bin, q{templates}, q{mip_} . $pipeline . q{_config.yaml} );
        $save_config_path =
          catfile( $Bin, q{mip_} . $pipeline . q{_config_} . $time_stamp . q{.yaml} );
        $log->info( q{Writing instructions to create config: } . $save_config_path );
    }

    ## Copy the config
    gnu_cp(
        {
            FILEHANDLE   => $FILEHANDLE,
            force        => 1,
            infile_path  => $load_config_path,
            outfile_path => $save_config_path,
        }
    );
    say {$FILEHANDLE} $NEWLINE;

    ## Load config
    my %config = load_yaml( { yaml_file => $load_config_path, } );
    my %config_environment = %{ $config{load_env} };

    ## Broadcast message
    my $status_message = q{## Updating/writing config if the installation was succesful};
    say {$FILEHANDLE} q{## Updating/writing config if the installation was succesful};
    gnu_echo(
        {
            FILEHANDLE  => $FILEHANDLE,
            strings_ref => [$status_message],
        }
    );
    say {$FILEHANDLE} $NEWLINE;

    say {$FILEHANDLE} q{SUCCESS_COUNTER=0};
  CONFIG_ENV_NAME:
    foreach my $config_env_name ( keys %config_environment ) {
        if (
            any { $_ eq $config_environment{$config_env_name}{installation} }
            @{$installations_ref}
          )
        {

            my $installation = $config_environment{$config_env_name}{installation};
            my $old_env_name = $config_env_name;
            my $new_env_name =
              $env_name_href->{ $config_environment{$config_env_name}{installation} };

            ## Build update_config_command
            my $update_config_command = build_update_config_command(
                {
                    new_env_name     => $new_env_name,
                    old_env_name     => $old_env_name,
                    save_config_path => $save_config_path,
                }
            );

            ## Create status messages
            my $success_message =
              qq{Updated config ($save_config_path) with $new_env_name};
            my $fail_message = q{\nFailed one or more installation tests in environment: }
              . $new_env_name . q{\n};
            $fail_message .= q{Config won't be updated/written for this environment\n};
            my $success_echo = join $SPACE,
              gnu_echo(
                {
                    enable_interpretation => 1,
                    strings_ref           => [$success_message],
                }
              );
            my $fail_echo = join $SPACE,
              gnu_echo(
                {
                    enable_interpretation => 1,
                    strings_ref           => [$fail_message],
                }
              );

            ## Check for success
            my $success_check =
              qq{if [[ "$installation_outcome{$installation}" == "success" ]]; then}
              . $NEWLINE;
            $success_check .= $TAB . $update_config_command . $NEWLINE;
            $success_check .= $TAB . $success_echo . $NEWLINE;
            $success_check .= $TAB . q{let "SUCCESS_COUNTER+=1"} . $NEWLINE;
            $success_check .= q{else} . $NEWLINE;
            $success_check .= $TAB . $fail_echo . $NEWLINE;
            $success_check .= q{fi};

            say {$FILEHANDLE} $success_check . $NEWLINE;
        }
        if ( not $config_environment{$config_env_name}{installation} ) {
            $log->warn(
qq{Automatic update of $load_config_path not possible. The config lacks information linking it to a MIP installation.}
            );
            gnu_rm(
                {
                    FILEHANDLE  => $FILEHANDLE,
                    force       => 1,
                    infile_path => $save_config_path,
                }
            );
            say {$FILEHANDLE} $NEWLINE;
            return;
        }
    }

    ## Rm temporary config if no installation was free from errors
    if ($write_config) {
        say {$FILEHANDLE}
          q{## Remove copied template config if no installation was succesful};

        # build_cleanup_check
        my $rm_temp_config = join $SPACE,
          gnu_rm(
            {
                force       => 1,
                infile_path => $save_config_path,
            }
          );
        my $cleanup_check = q{if [[ "$SUCCESS_COUNTER" -eq 0 ]]; then} . $NEWLINE;
        $cleanup_check .= $TAB . $rm_temp_config . $NEWLINE;
        $cleanup_check .= q{fi};
        say {$FILEHANDLE} $cleanup_check;
    }
    return;
}

sub build_perl_program_check_command {

## Function : Build perl oneliner for testing program installation
## Returns  : $perl_commands
## Arguments: $programs_ref                => Programs to check {REF}
##          : $program_test_command_href  => Hash with test commands {REF}

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $programs_ref;
    my $program_test_command_href;

    my $tmpl = {
        programs_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$programs_ref,
            strict_type => 1,
        },
        program_test_command_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$program_test_command_href,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    ## Constants
    Readonly my $SEMICOLON    => q{;};
    Readonly my $OPEN_STRING  => q/q{/;
    Readonly my $CLOSE_STRING => q/}/;
    Readonly my $TIMEOUT      => 20;

    ## Array for storing test commands
    my @program_test_commands;

  PROGRAM:
    foreach my $program ( @{$programs_ref} ) {

        ## Skip programs that lacks a test_command
        next PROGRAM if ( not $program_test_command_href->{$program} );

        ## Add path test
        if ( $program_test_command_href->{$program}{path} ) {
            my $path_test =
              $OPEN_STRING . $program_test_command_href->{$program}{path} . $CLOSE_STRING;
            my $path_test_name =
              $OPEN_STRING . q{Program in path: } . $program . $CLOSE_STRING;
            my $path_test_command =
              qq{ok(can_run( $path_test ), $path_test_name)} . $SEMICOLON;
            push @program_test_commands, $path_test_command;
        }
        ## Add execution test
        if ( $program_test_command_href->{$program}{execution} ) {
            my $execution_test =
                $OPEN_STRING
              . $program_test_command_href->{$program}{execution}
              . $CLOSE_STRING;
            my $execution_test_name =
              $OPEN_STRING . q{Can execute: } . $program . $CLOSE_STRING;
            my $execution_test_command =
qq{ok(run(command => $execution_test, timeout => $TIMEOUT), $execution_test_name)}
              . $SEMICOLON;
            push @program_test_commands, $execution_test_command;
        }
    }

    ## Return nothing if no tests are available for the programs
    return if ( not scalar @program_test_commands );

    ## Start perl oneliner
    my @perl_commands = q{perl -e};

    ## Add opening quote
    push @perl_commands, $SINGLE_QUOTE;

    ## Add required IPC module
    push @perl_commands, q{use IPC::Cmd qw{ can_run run };};

    ## Add required IPC module
    push @perl_commands, q{use Test::More;};

    ## Add program tests
    @perl_commands = ( @perl_commands, @program_test_commands );

    ## Done testing
    push @perl_commands, q{done_testing;};

    ## Add closing single quote
    push @perl_commands, $SINGLE_QUOTE;

    return @perl_commands;
}

sub build_update_config_command {

## Function : Build perl oneliner for updating the config with new environment names
## Returns  : $update_config_command
## Arguments: $new_env_name     => New environment name
##          : $old_env_name     => Old environment name
##          : $save_config_path => Path to config that will be updated

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $new_env_name;
    my $old_env_name;
    my $save_config_path;

    my $tmpl = {
        new_env_name => {
            defined     => 1,
            required    => 1,
            store       => \$new_env_name,
            strict_type => 1,
        },
        old_env_name => {
            defined     => 1,
            required    => 1,
            store       => \$old_env_name,
            strict_type => 1,
        },
        save_config_path => {
            defined     => 1,
            required    => 1,
            store       => \$save_config_path,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    ## Start perl oneliner
    my $perl_replace = q{perl -pi -e };

    ## Substitute occurences of old_name followed by ":" or "/"
    $perl_replace .= q{'s/} . $old_env_name . q{(?=[\/:])};

    ## with new_name
    $perl_replace .= q{/} . $new_env_name . q{/xms'};

    ## Add config to update
    my $update_config_command = $perl_replace . $SPACE . $save_config_path;

    return $update_config_command;
}

1;
