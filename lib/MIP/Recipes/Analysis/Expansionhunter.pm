package MIP::Recipes::Analysis::Expansionhunter;

use 5.026;
use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
use File::Basename qw{ dirname };
use File::Spec::Functions qw{ catdir catfile };
use open qw{ :encoding(UTF-8) :std };
use Params::Check qw{ check allow last_error };
use strict;
use utf8;
use warnings;
use warnings qw{ FATAL utf8 };

## CPANM
use autodie qw{ :all };
use Readonly;

BEGIN {

    require Exporter;
    use base qw{ Exporter };

    # Set the version for version checking
    our $VERSION = 1.07;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw{ analysis_expansionhunter };

}

## Constants
Readonly my $ASTERISK   => q{*};
Readonly my $AMPERSAND  => q{&};
Readonly my $DOT        => q{.};
Readonly my $NEWLINE    => qq{\n};
Readonly my $UNDERSCORE => q{_};

sub analysis_expansionhunter {

## Function : Call expansions of Short Tandem Repeats (STR) using Expansion Hunter
## Returns  :
##          : $active_parameter_href   => Active parameters for this analysis hash {REF}
##          : $case_id                 => Family id
##          : $file_info_href          => The file_info hash {REF}
##          : $infile_lane_prefix_href => Infile(s) without the ".ending" {REF}
##          : $job_id_href             => Job id hash {REF}
##          : $parameter_href          => Parameter hash {REF}
##          : $profile_base_command    => Submission profile base command
##          : $recipe_name             => Program name
##          : $reference_dir           => MIP reference directory
##          : $sample_info_href        => Info on samples and case hash {REF}
##          : $temp_directory          => Temporary directory

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $active_parameter_href;
    my $file_info_href;
    my $infile_lane_prefix_href;
    my $job_id_href;
    my $parameter_href;
    my $recipe_name;
    my $sample_info_href;

    ## Default(s)
    my $case_id;
    my $profile_base_command;
    my $reference_dir;
    my $temp_directory;

    my $tmpl = {
        active_parameter_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$active_parameter_href,
            strict_type => 1,
        },
        case_id => {
            default     => $arg_href->{active_parameter_href}{case_id},
            store       => \$case_id,
            strict_type => 1,
        },
        file_info_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$file_info_href,
            strict_type => 1,
        },
        infile_lane_prefix_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$infile_lane_prefix_href,
            strict_type => 1,
        },
        job_id_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$job_id_href,
            strict_type => 1,
        },
        parameter_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$parameter_href,
            strict_type => 1,
        },
        profile_base_command => {
            default     => q{sbatch},
            store       => \$profile_base_command,
            strict_type => 1,
        },
        recipe_name => {
            defined     => 1,
            required    => 1,
            store       => \$recipe_name,
            strict_type => 1,
        },
        reference_dir => {
            default     => $arg_href->{active_parameter_href}{reference_dir},
            store       => \$reference_dir,
            strict_type => 1,
        },
        sample_info_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$sample_info_href,
            strict_type => 1,
        },
        temp_directory => {
            default     => $arg_href->{active_parameter_href}{temp_directory},
            store       => \$temp_directory,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    use MIP::Cluster qw{ get_core_number };
    use MIP::Get::File qw{ get_io_files };
    use MIP::Get::Parameter
      qw{ get_package_source_env_cmds get_recipe_attributes get_recipe_parameters };
    use MIP::Gnu::Coreutils qw{ gnu_mv };
    use MIP::IO::Files qw{ migrate_file };
    use MIP::Parse::File qw{ parse_io_outfiles };
    use MIP::Processmanagement::Processes qw{ print_wait submit_recipe };
    use MIP::Program::Variantcalling::Bcftools
      qw{ bcftools_rename_vcf_samples bcftools_view };
    use MIP::Program::Variantcalling::Expansionhunter qw{ expansionhunter };
    use MIP::Program::Variantcalling::Stranger qw{ stranger };
    use MIP::Program::Variantcalling::Svdb qw{ svdb_merge };
    use MIP::Program::Variantcalling::Vt qw{ vt_decompose };
    use MIP::QC::Sample_info qw{ set_recipe_outfile_in_sample_info };
    use MIP::Script::Setup_script
      qw{ setup_script write_return_to_environment write_source_environment_command };

    ### PREPROCESSING:

    ## Retrieve logger object
    my $log = Log::Log4perl->get_logger(q{MIP});

    ## Unpack parameters
    my $max_cores_per_node = $active_parameter_href->{max_cores_per_node};
    my $modifier_core_number =
      scalar( @{ $active_parameter_href->{sample_ids} } );
    my $human_genome_reference =
      $arg_href->{active_parameter_href}{human_genome_reference};
    my $job_id_chain = get_recipe_attributes(
        {
            parameter_href => $parameter_href,
            recipe_name    => $recipe_name,
            attribute      => q{chain},
        }
    );
    my $recipe_mode = $active_parameter_href->{$recipe_name};
    my $repeat_specs_dir_path =
      $active_parameter_href->{expansionhunter_repeat_specs_dir};
    my ( $core_number, $time, @source_environment_cmds ) = get_recipe_parameters(
        {
            active_parameter_href => $active_parameter_href,
            recipe_name           => $recipe_name,
        }
    );

    ## Set and get the io files per chain, id and stream
    my %io = parse_io_outfiles(
        {
            chain_id               => $job_id_chain,
            id                     => $case_id,
            file_info_href         => $file_info_href,
            file_name_prefixes_ref => [$case_id],
            outdata_dir            => $active_parameter_href->{outdata_dir},
            parameter_href         => $parameter_href,
            recipe_name            => $recipe_name,
            temp_directory         => $temp_directory,
        }
    );

    my $outdir_path_prefix       = $io{out}{dir_path_prefix};
    my $outfile_path_prefix      = $io{out}{file_path_prefix};
    my $outfile_suffix           = $io{out}{file_constant_suffix};
    my $outfile_path             = $outfile_path_prefix . $outfile_suffix;
    my $temp_outfile_path_prefix = $io{temp}{file_path_prefix};
    my $temp_outfile_suffix      = $io{temp}{file_suffix};
    my $temp_outfile_path        = $temp_outfile_path_prefix . $temp_outfile_suffix;
    my $temp_file_suffix         = $DOT . q{vcf};

    ## Filehandles
    # Create anonymous filehandle
    my $FILEHANDLE = IO::Handle->new();

    $core_number = get_core_number(
        {
            max_cores_per_node   => $max_cores_per_node,
            modifier_core_number => $modifier_core_number,
            recipe_core_number   => $core_number,
        }
    );

    ## Creates recipe directories (info & data & script), recipe script filenames and writes sbatch header
    my ( $recipe_file_path, $recipe_info_path ) = setup_script(
        {
            active_parameter_href           => $active_parameter_href,
            core_number                     => $core_number,
            directory_id                    => $case_id,
            FILEHANDLE                      => $FILEHANDLE,
            job_id_href                     => $job_id_href,
            log                             => $log,
            process_time                    => $time,
            recipe_directory                => $recipe_name,
            recipe_name                     => $recipe_name,
            source_environment_commands_ref => \@source_environment_cmds,
            temp_directory                  => $temp_directory,
        }
    );

    ### SHELL:

    my %exphun_sample_file_info;
    my $process_batches_count = 1;

    ## Collect infiles for all sample_ids to enable migration to temporary directory
  SAMPLE_ID:
    while ( my ( $sample_id_index, $sample_id ) =
        each @{ $active_parameter_href->{sample_ids} } )
    {

        ## Get the io infiles per chain and id
        my %sample_io = get_io_files(
            {
                id             => $sample_id,
                file_info_href => $file_info_href,
                parameter_href => $parameter_href,
                recipe_name    => $recipe_name,
                stream         => q{in},
                temp_directory => $temp_directory,
            }
        );
        my $infile_path_prefix = $sample_io{in}{file_path_prefix};
        my $infile_suffix      = $sample_io{in}{file_suffix};
        my $infile_path =
          $infile_path_prefix . substr( $infile_suffix, 0, 2 ) . $ASTERISK;
        my $temp_infile_path_prefix = $sample_io{temp}{file_path_prefix};
        my $temp_infile_path        = $temp_infile_path_prefix . $infile_suffix;

        $exphun_sample_file_info{$sample_id}{in}  = $temp_infile_path;
        $exphun_sample_file_info{$sample_id}{out} = $temp_infile_path_prefix;

        $process_batches_count = print_wait(
            {
                FILEHANDLE            => $FILEHANDLE,
                max_process_number    => $core_number,
                process_batches_count => $process_batches_count,
                process_counter       => $sample_id_index,
            }
        );

        ## Copy file(s) to temporary directory
        say {$FILEHANDLE} q{## Copy file(s) to temporary directory};
        migrate_file(
            {
                FILEHANDLE   => $FILEHANDLE,
                infile_path  => $infile_path,
                outfile_path => $temp_directory,
            }
        );
    }
    say {$FILEHANDLE} q{wait}, $NEWLINE;

    ## Rename the bam file index file so that Expansion Hunter can find it
    say {$FILEHANDLE} q{## Rename index file};
  SAMPLE_ID:
    foreach my $sample_id ( @{ $active_parameter_href->{sample_ids} } ) {

        gnu_mv(
            {
                FILEHANDLE   => $FILEHANDLE,
                infile_path  => $exphun_sample_file_info{$sample_id}{out} . q{.bai},
                outfile_path => $exphun_sample_file_info{$sample_id}{in} . q{.bai},
            }
        );
        say {$FILEHANDLE} $NEWLINE;
    }

    ## Run Expansion Hunter
    say {$FILEHANDLE} q{## Run ExpansionHunter};

    # Restart counter
    $process_batches_count = 1;

    ## Expansion hunter calling per sample id
  SAMPLE_ID:
    while ( my ( $sample_id_index, $sample_id ) =
        each @{ $active_parameter_href->{sample_ids} } )
    {

        $process_batches_count = print_wait(
            {
                FILEHANDLE            => $FILEHANDLE,
                max_process_number    => $core_number,
                process_batches_count => $process_batches_count,
                process_counter       => $sample_id_index,
            }
        );

        my $sample_sex = $sample_info_href->{sample}{$sample_id}{sex};
        expansionhunter(
            {
                FILEHANDLE        => $FILEHANDLE,
                infile_path       => $exphun_sample_file_info{$sample_id}{in},
                json_outfile_path => $exphun_sample_file_info{$sample_id}{out}
                  . $DOT . q{json},
                log_outfile_path => $exphun_sample_file_info{$sample_id}{out}
                  . $DOT . q{log},
                reference_genome_path => $human_genome_reference,
                repeat_specs_dir_path => $repeat_specs_dir_path,
                sex                   => $sample_sex,
                vcf_outfile_path      => $exphun_sample_file_info{$sample_id}{out}
                  . $temp_file_suffix,
            }
        );
        say {$FILEHANDLE} $AMPERSAND, $NEWLINE;
    }
    say {$FILEHANDLE} q{wait}, $NEWLINE;

    ## Get parameters
    ## Expansionhunter sample infiles needs to be lexiographically sorted for svdb merge
    my @svdb_temp_infile_paths =
      map { $exphun_sample_file_info{$_}{out} . $temp_file_suffix }
      @{ $active_parameter_href->{sample_ids} };
    my $svdb_temp_outfile_path =
      $temp_outfile_path_prefix . $UNDERSCORE . q{svdbmerge} . $temp_file_suffix;

    my @program_source_commands = get_package_source_env_cmds(
        {
            active_parameter_href => $active_parameter_href,
            package_name          => q{svdb},
        }
    );

    write_source_environment_command(
        {
            FILEHANDLE                      => $FILEHANDLE,
            source_environment_commands_ref => \@program_source_commands,
        }
    );

    svdb_merge(
        {
            FILEHANDLE       => $FILEHANDLE,
            infile_paths_ref => \@svdb_temp_infile_paths,
            notag            => 1,
            stdoutfile_path  => $svdb_temp_outfile_path,
        }
    );
    say {$FILEHANDLE} $NEWLINE;

    write_return_to_environment(
        {
            active_parameter_href => $active_parameter_href,
            FILEHANDLE            => $FILEHANDLE,
        }
    );
    print {$FILEHANDLE} $NEWLINE;

    ## Split multiallelic variants
    say {$FILEHANDLE} q{## Split multiallelic variants};
    my $vt_temp_outfile_path =
      $temp_outfile_path_prefix . $UNDERSCORE . q{svdbmerg_vt} . $temp_file_suffix;
    vt_decompose(
        {
            FILEHANDLE          => $FILEHANDLE,
            infile_path         => $svdb_temp_outfile_path,
            outfile_path        => $vt_temp_outfile_path,
            smart_decomposition => 1,
        }
    );
    say {$FILEHANDLE} $NEWLINE;

    @program_source_commands = get_package_source_env_cmds(
        {
            active_parameter_href => $active_parameter_href,
            package_name          => q{stranger},
        }
    );

    write_source_environment_command(
        {
            FILEHANDLE                      => $FILEHANDLE,
            source_environment_commands_ref => \@program_source_commands,
        }
    );
    say {$FILEHANDLE} q{## Stranger annotation};

    my $stranger_outfile_path =
      $temp_outfile_path_prefix . $UNDERSCORE . q{svdbmerg_vt_ann} . $temp_file_suffix;
    stranger(
        {
            FILEHANDLE      => $FILEHANDLE,
            infile_path     => $vt_temp_outfile_path,
            stdoutfile_path => $stranger_outfile_path,
        }
    );
    say {$FILEHANDLE} $NEWLINE;

    say {$FILEHANDLE} q{## Adding sample id instead of file prefix};

    bcftools_rename_vcf_samples(
        {
            FILEHANDLE          => $FILEHANDLE,
            index               => 1,
            index_type          => q{csi},
            infile              => $stranger_outfile_path,
            outfile_path_prefix => $outfile_path_prefix,
            output_type         => q{z},
            temp_directory      => $temp_directory,
            sample_ids_ref      => \@{ $active_parameter_href->{sample_ids} },
        }
    );

    close $FILEHANDLE;

    if ( $recipe_mode == 1 ) {

        set_recipe_outfile_in_sample_info(
            {
                sample_info_href => $sample_info_href,
                recipe_name      => q{expansionhunter},
                path             => $outfile_path,
            }
        );

        submit_recipe(
            {
                base_command            => $profile_base_command,
                dependency_method       => q{sample_to_case},
                case_id                 => $case_id,
                infile_lane_prefix_href => $infile_lane_prefix_href,
                job_id_href             => $job_id_href,
                log                     => $log,
                job_id_chain            => $job_id_chain,
                recipe_file_path        => $recipe_file_path,
                sample_ids_ref          => \@{ $active_parameter_href->{sample_ids} },
                submission_profile      => $active_parameter_href->{submission_profile},
            }
        );
    }
    return 1;
}

1;
