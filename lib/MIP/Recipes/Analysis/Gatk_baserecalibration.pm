package MIP::Recipes::Analysis::Gatk_baserecalibration;

use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
use File::Basename qw{ basename };
use File::Spec::Functions qw{ catdir catfile };
use open qw{ :encoding(UTF-8) :std };
use Params::Check qw{ allow check last_error };
use POSIX;
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
    our $VERSION = 1.10;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK =
      qw{ analysis_gatk_baserecalibration analysis_gatk_baserecalibration_rio };

}

## Constants
Readonly my $ASTERISK   => q{*};
Readonly my $DOT        => q{.};
Readonly my $NEWLINE    => qq{\n};
Readonly my $UNDERSCORE => q{_};
Readonly my $MINUS_ONE  => -1;

sub analysis_gatk_baserecalibration {

## Function : GATK baserecalibrator/GatherBQSRReports/ApplyBQSR to recalibrate bases before variant calling. BaseRecalibrator/GatherBQSRReports/ApplyBQSR will be executed within the same sbatch script.
## Returns  :
## Arguments: $active_parameter_href   => Active parameters for this analysis hash {REF}
##          : $case_id                 => Family id
##          : $file_info_href          => File info hash {REF}
##          : $infile_lane_prefix_href => Infile(s) without the ".ending" {REF}
##          : $job_id_href             => Job id hash {REF}
##          : $parameter_href          => Parameter hash {REF}
##          : $profile_base_command    => Submission profile base command
##          : $recipe_name             => Program name
##          : $sample_id               => Sample id
##          : $sample_info_href        => Info on samples and case hash {REF}
##          : $temp_directory          => Temporary directory
##          : $xargs_file_counter      => The xargs file counter

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $active_parameter_href;
    my $file_info_href;
    my $infile_lane_prefix_href;
    my $job_id_href;
    my $parameter_href;
    my $recipe_name;
    my $sample_info_href;
    my $sample_id;

    ## Default(s)
    my $case_id;
    my $profile_base_command;
    my $temp_directory;
    my $xargs_file_counter;

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
        sample_info_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$sample_info_href,
            strict_type => 1,
        },
        sample_id => {
            defined     => 1,
            required    => 1,
            store       => \$sample_id,
            strict_type => 1,
        },
        temp_directory => {
            default     => $arg_href->{active_parameter_href}{temp_directory},
            store       => \$temp_directory,
            strict_type => 1,
        },
        xargs_file_counter => {
            allow       => qr/ ^\d+$ /xsm,
            default     => 0,
            store       => \$xargs_file_counter,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    use MIP::Cluster qw{ get_memory_constrained_core_number };
    use MIP::Get::File qw{ get_merged_infile_prefix get_io_files };
    use MIP::Get::Parameter
      qw{ get_gatk_intervals get_recipe_parameters get_recipe_attributes };
    use MIP::IO::Files qw{ migrate_file xargs_migrate_contig_files };
    use MIP::Parse::File qw{ parse_io_outfiles };
    use MIP::Processmanagement::Processes qw{ submit_recipe };
    use MIP::Program::Alignment::Gatk
      qw{ gatk_applybqsr gatk_baserecalibrator gatk_gatherbqsrreports };
    use MIP::Program::Alignment::Picardtools qw{ picardtools_gatherbamfiles };
    use MIP::QC::Sample_info
      qw{ set_recipe_outfile_in_sample_info set_recipe_metafile_in_sample_info set_processing_metafile_in_sample_info };
    use MIP::Recipes::Analysis::Xargs qw{ xargs_command };
    use MIP::Script::Setup_script qw{ setup_script };

    ### PREPROCESSING:

    ## Retrieve logger object
    my $log = Log::Log4perl->get_logger(q{MIP});

    ## Unpack parameters
    ## Get the io infiles per chain and id
    my %io = get_io_files(
        {
            id             => $sample_id,
            file_info_href => $file_info_href,
            parameter_href => $parameter_href,
            recipe_name    => $recipe_name,
            stream         => q{in},
            temp_directory => $temp_directory,
        }
    );
    my $indir_path_prefix  = $io{in}{dir_path_prefix};
    my $infile_suffix      = $io{in}{file_suffix};
    my $infile_name_prefix = $io{in}{file_name_prefix};
    my %temp_infile_path   = %{ $io{temp}{file_path_href} };

    my %rec_atr = get_recipe_attributes(
        {
            parameter_href => $parameter_href,
            recipe_name    => $recipe_name,
        }
    );
    my $job_id_chain       = $rec_atr{chain};
    my $recipe_mode        = $active_parameter_href->{$recipe_name};
    my $referencefile_path = $active_parameter_href->{human_genome_reference};
    my $analysis_type      = $active_parameter_href->{analysis_type}{$sample_id};
    my $xargs_file_path_prefix;
    my ( $core_number, $time, @source_environment_cmds ) = get_recipe_parameters(
        {
            active_parameter_href => $active_parameter_href,
            recipe_name           => $recipe_name,
        }
    );

    ## Add merged infile name prefix after merging all BAM files per sample_id
    my $merged_infile_prefix = get_merged_infile_prefix(
        {
            file_info_href => $file_info_href,
            sample_id      => $sample_id,
        }
    );

    ## Outpaths
    ## Assign suffix
    my $outfile_suffix = $rec_atr{outfile_suffix};
    my $outsample_directory =
      catdir( $active_parameter_href->{outdata_dir}, $sample_id, $recipe_name );
    my $outfile_tag =
      $file_info_href->{$sample_id}{$recipe_name}{file_tag};
    my @outfile_paths =
      map {
        catdir( $outsample_directory,
            $merged_infile_prefix . $outfile_tag . $DOT . $_ . $outfile_suffix )
      } @{ $file_info_href->{contigs_size_ordered} };

    ## Set and get the io files per chain, id and stream
    %io = (
        %io,
        parse_io_outfiles(
            {
                chain_id       => $job_id_chain,
                id             => $sample_id,
                file_info_href => $file_info_href,
                file_paths_ref => \@outfile_paths,
                parameter_href => $parameter_href,
                recipe_name    => $recipe_name,
                temp_directory => $temp_directory,
            }
        )
    );

    my $outdir_path_prefix       = $io{out}{dir_path_prefix};
    my $outfile_name_prefix      = $io{out}{file_name_prefix};
    my $temp_outfile_path_prefix = $io{temp}{file_path_prefix};
    my %temp_outfile_path        = %{ $io{temp}{file_path_href} };

    ## Filehandles
    # Create anonymous filehandle
    my $FILEHANDLE      = IO::Handle->new();
    my $XARGSFILEHANDLE = IO::Handle->new();

    ## Creates recipe directories (info & data & script), recipe script filenames and writes sbatch header
    my ( $recipe_file_path, $recipe_info_path ) = setup_script(
        {
            active_parameter_href           => $active_parameter_href,
            core_number                     => $core_number,
            directory_id                    => $sample_id,
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

    ## Generate gatk intervals. Chromosomes for WGS/WTS and paths to contig_bed_files for WES
    my %gatk_intervals = get_gatk_intervals(
        {
            analysis_type         => $analysis_type,
            contigs_ref           => \@{ $file_info_href->{contigs_size_ordered} },
            exome_target_bed_href => $active_parameter_href->{exome_target_bed},
            FILEHANDLE            => $FILEHANDLE,
            file_ending           => $file_info_href->{exome_target_bed}[0],
            max_cores_per_node    => $core_number,
            log                   => $log,
            outdirectory          => $temp_directory,
            reference_dir         => $active_parameter_href->{reference_dir},
            sample_id             => $sample_id,
        }
    );

    ## Copy file(s) to temporary directory
    say {$FILEHANDLE} q{## Copy file(s) to temporary directory};
    ($xargs_file_counter) = xargs_migrate_contig_files(
        {
            contigs_ref        => \@{ $file_info_href->{contigs_size_ordered} },
            core_number        => $core_number,
            indirectory        => $indir_path_prefix,
            infile             => $infile_name_prefix,
            FILEHANDLE         => $FILEHANDLE,
            file_ending        => substr( $infile_suffix, 0, 2 ) . $ASTERISK,
            file_path          => $recipe_file_path,
            recipe_info_path   => $recipe_info_path,
            XARGSFILEHANDLE    => $XARGSFILEHANDLE,
            xargs_file_counter => $xargs_file_counter,
            temp_directory     => $temp_directory,
        }
    );

    ## Division by X according to the java heap
    Readonly my $JAVA_MEMORY_ALLOCATION => 6;

    # Constrain parallelization to match available memory
    my $program_core_number = get_memory_constrained_core_number(
        {
            max_cores_per_node => $active_parameter_href->{max_cores_per_node},
            memory_allocation  => $JAVA_MEMORY_ALLOCATION,
            node_ram_memory    => $active_parameter_href->{node_ram_memory},
            recipe_core_number => $core_number,
        }
    );

    ## GATK BaseRecalibrator
    say {$FILEHANDLE} q{## GATK BaseRecalibrator};

    ## Create file commands for xargs
    ( $xargs_file_counter, $xargs_file_path_prefix ) = xargs_command(
        {
            core_number        => $program_core_number,
            FILEHANDLE         => $FILEHANDLE,
            file_path          => $recipe_file_path,
            recipe_info_path   => $recipe_info_path,
            XARGSFILEHANDLE    => $XARGSFILEHANDLE,
            xargs_file_counter => $xargs_file_counter,
        }
    );

    my @base_quality_score_recalibration_files;
  CONTIG:
    foreach my $contig ( @{ $file_info_href->{contigs_size_ordered} } ) {

        my $base_quality_score_recalibration_file =
          $temp_outfile_path_prefix . $DOT . $contig . $DOT . q{grp};

        ## Add for gathering base recal files later
        push @base_quality_score_recalibration_files,
          $base_quality_score_recalibration_file;
        my $stderrfile_path =
          $xargs_file_path_prefix . $DOT . $contig . $DOT . q{stderr.txt};
        gatk_baserecalibrator(
            {
                FILEHANDLE           => $XARGSFILEHANDLE,
                infile_path          => $temp_infile_path{$contig},
                intervals_ref        => $gatk_intervals{$contig},
                java_use_large_pages => $active_parameter_href->{java_use_large_pages},
                known_sites_ref =>
                  \@{ $active_parameter_href->{gatk_baserecalibration_known_sites} },
                memory_allocation  => q{Xmx} . $JAVA_MEMORY_ALLOCATION . q{g},
                outfile_path       => $base_quality_score_recalibration_file,
                referencefile_path => $referencefile_path,
                stderrfile_path    => $stderrfile_path,
                temp_directory     => $temp_directory,
                verbosity          => $active_parameter_href->{gatk_logging_level},
                xargs_mode         => 1,
            }
        );
        say {$XARGSFILEHANDLE} $NEWLINE;
    }

    ## GATK GatherBQSRReports
    say {$FILEHANDLE} q{## GATK GatherBQSRReports};
    my $gatk_gatherbqsr_outfile_path =
      $temp_outfile_path_prefix . $DOT . $sample_id . $DOT . q{grp};
    gatk_gatherbqsrreports(
        {
            base_quality_score_recalibration_files_ref =>
              \@base_quality_score_recalibration_files,
            FILEHANDLE   => $FILEHANDLE,
            outfile_path => $gatk_gatherbqsr_outfile_path,
        }
    );
    say {$FILEHANDLE} $NEWLINE;

    ## GATK ApplyBQSR
    say {$FILEHANDLE} q{## GATK ApplyBQSR};

    ## Create file commands for xargs
    ( $xargs_file_counter, $xargs_file_path_prefix ) = xargs_command(
        {
            core_number        => $program_core_number,
            FILEHANDLE         => $FILEHANDLE,
            file_path          => $recipe_file_path,
            recipe_info_path   => $recipe_info_path,
            XARGSFILEHANDLE    => $XARGSFILEHANDLE,
            xargs_file_counter => $xargs_file_counter,
        }
    );

  CONTIG:
    foreach my $contig ( @{ $file_info_href->{contigs_size_ordered} } ) {

        my $stderrfile_path =
          $xargs_file_path_prefix . $DOT . $contig . $DOT . q{stderr.txt};
        gatk_applybqsr(
            {
                base_quality_score_recalibration_file => $gatk_gatherbqsr_outfile_path,
                FILEHANDLE                            => $XARGSFILEHANDLE,
                infile_path                           => $temp_infile_path{$contig},
                intervals_ref                         => $gatk_intervals{$contig},
                java_use_large_pages => $active_parameter_href->{java_use_large_pages},
                memory_allocation    => q{Xmx} . $JAVA_MEMORY_ALLOCATION . q{g},
                verbosity            => $active_parameter_href->{gatk_logging_level},
                read_filters_ref =>
                  \@{ $active_parameter_href->{gatk_baserecalibration_read_filters} },
                referencefile_path         => $referencefile_path,
                static_quantized_quals_ref => \@{
                    $active_parameter_href
                      ->{gatk_baserecalibration_static_quantized_quals}
                },
                outfile_path       => $temp_outfile_path{$contig},
                referencefile_path => $referencefile_path,
                stderrfile_path    => $stderrfile_path,
                temp_directory     => $temp_directory,
                xargs_mode         => 1,
            }
        );
        say {$XARGSFILEHANDLE} $NEWLINE;
    }

    ## Copies file from temporary directory. Per contig for variant callers.
    say {$FILEHANDLE} q{## Copy file from temporary directory};
    ($xargs_file_counter) = xargs_migrate_contig_files(
        {
            contigs_ref        => \@{ $file_info_href->{contigs_size_ordered} },
            core_number        => $core_number,
            FILEHANDLE         => $FILEHANDLE,
            file_ending        => substr( $outfile_suffix, 0, 2 ) . $ASTERISK,
            file_path          => $recipe_file_path,
            outdirectory       => $outdir_path_prefix,
            outfile            => $outfile_name_prefix,
            recipe_info_path   => $recipe_info_path,
            temp_directory     => $temp_directory,
            XARGSFILEHANDLE    => $XARGSFILEHANDLE,
            xargs_file_counter => $xargs_file_counter,
        }
    );

    ## Gather BAM files
    say {$FILEHANDLE} q{## Gather BAM files};

    ## Assemble infile paths in contig order and not per size
    my @gather_infile_paths =
      map { $temp_outfile_path{$_} } @{ $file_info_href->{contigs} };

    picardtools_gatherbamfiles(
        {
            create_index     => q{true},
            FILEHANDLE       => $FILEHANDLE,
            infile_paths_ref => \@gather_infile_paths,
            java_jar =>
              catfile( $active_parameter_href->{picardtools_path}, q{picard.jar} ),
            java_use_large_pages => $active_parameter_href->{java_use_large_pages},
            memory_allocation    => q{Xmx4g},
            outfile_path         => $temp_outfile_path_prefix . $outfile_suffix,
            referencefile_path   => $referencefile_path,
            temp_directory       => $temp_directory,
        }
    );
    say {$FILEHANDLE} $NEWLINE;

    ## Copies file from temporary directory.
    say {$FILEHANDLE} q{## Copy file from temporary directory};
    migrate_file(
        {
            FILEHANDLE  => $FILEHANDLE,
            infile_path => $temp_outfile_path_prefix
              . substr( $outfile_suffix, 0, 2 )
              . $ASTERISK,
            outfile_path => $outdir_path_prefix,
        }
    );
    say {$FILEHANDLE} q{wait}, $NEWLINE;

    close $XARGSFILEHANDLE;
    close $FILEHANDLE;

    if ( $recipe_mode == 1 ) {

        my $gathered_outfile_path =
          catfile( $outdir_path_prefix, $outfile_name_prefix . $outfile_suffix );

        ## Collect QC metadata info for later use
        set_recipe_outfile_in_sample_info(
            {
                infile           => $outfile_name_prefix,
                path             => $gathered_outfile_path,
                recipe_name      => $recipe_name,
                sample_id        => $sample_id,
                sample_info_href => $sample_info_href,
            }
        );
        my $most_complete_format_key =
          q{most_complete} . $UNDERSCORE . substr $outfile_suffix, 1;
        set_processing_metafile_in_sample_info(
            {
                metafile_tag     => $most_complete_format_key,
                path             => $gathered_outfile_path,
                sample_id        => $sample_id,
                sample_info_href => $sample_info_href,
            }
        );

        submit_recipe(
            {
                base_command            => $profile_base_command,
                case_id                 => $case_id,
                dependency_method       => q{sample_to_sample},
                infile_lane_prefix_href => $infile_lane_prefix_href,
                job_id_chain            => $job_id_chain,
                job_id_href             => $job_id_href,
                log                     => $log,
                recipe_file_path        => $recipe_file_path,
                sample_id               => $sample_id,
                submission_profile      => $active_parameter_href->{submission_profile},
            }
        );
    }
    return 1;
}

sub analysis_gatk_baserecalibration_rio {

## Function : GATK baserecalibrator/GatherBQSRReports/ApplyBQSR to recalibrate bases before variant calling. BaseRecalibrator/GatherBQSRReports/ApplyBQSR will be executed within the same sbatch script.
## Returns  :
## Arguments: $active_parameter_href   => Active parameters for this analysis hash {REF}
##          : $case_id                 => Family id
##          : $FILEHANDLE              => Filehandle to write to
##          : $file_info_href          => File info hash {REF}
##          : $file_path               => File path
##          : $infile_lane_prefix_href => Infile(s) without the ".ending" {REF}
##          : $job_id_href             => Job id hash {REF}
##          : $parameter_href          => Parameter hash {REF}
##          : $profile_base_command    => Submission profile base command
##          : $recipe_info_path        => Recipe info path
##          : $recipe_name             => Program name
##          : $sample_id               => Sample id
##          : $sample_info_href        => Info on samples and case hash {REF}
##          : $temp_directory          => Temporary directory
##          : $xargs_file_counter      => The xargs file counter

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $active_parameter_href;
    my $FILEHANDLE;
    my $file_info_href;
    my $file_path;
    my $infile_lane_prefix_href;
    my $job_id_href;
    my $parameter_href;
    my $recipe_name;
    my $recipe_info_path;
    my $sample_id;
    my $sample_info_href;

    ## Default(s)
    my $case_id;
    my $profile_base_command;
    my $temp_directory;
    my $xargs_file_counter;

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
        FILEHANDLE     => { store => \$FILEHANDLE, },
        file_info_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$file_info_href,
            strict_type => 1,
        },
        file_path               => { store => \$file_path, strict_type => 1, },
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
        recipe_info_path => { store => \$recipe_info_path, strict_type => 1, },
        recipe_name      => {
            defined     => 1,
            required    => 1,
            store       => \$recipe_name,
            strict_type => 1,
        },
        sample_id => {
            defined     => 1,
            required    => 1,
            store       => \$sample_id,
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
        xargs_file_counter => {
            allow       => qr/ ^\d+$ /xsm,
            default     => 0,
            store       => \$xargs_file_counter,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    use MIP::Cluster qw{ get_memory_constrained_core_number };
    use MIP::Delete::File qw{ delete_contig_files };
    use MIP::File::Interval qw{ generate_contig_interval_file };
    use MIP::Get::File
      qw{ get_exom_target_bed_file get_merged_infile_prefix get_io_files};
    use MIP::Get::Parameter
      qw{ get_gatk_intervals get_recipe_parameters get_recipe_attributes };
    use MIP::IO::Files qw{ migrate_file xargs_migrate_contig_files };
    use MIP::Parse::File qw{ parse_io_outfiles };
    use MIP::Processmanagement::Slurm_processes
      qw{ slurm_submit_job_sample_id_dependency_add_to_sample };
    use MIP::Program::Alignment::Gatk
      qw{ gatk_applybqsr gatk_baserecalibrator gatk_gatherbqsrreports };
    use MIP::Program::Alignment::Picardtools qw{ picardtools_gatherbamfiles };
    use MIP::QC::Sample_info
      qw{ set_recipe_outfile_in_sample_info set_recipe_metafile_in_sample_info };
    use MIP::Recipes::Analysis::Xargs qw{ xargs_command };

    ### PREPROCESSING:

    ## Retrieve logger object
    my $log = Log::Log4perl->get_logger(q{MIP});

    ## Unpack parameters
    ## Get the io infiles per chain and id
    my %io = get_io_files(
        {
            id             => $sample_id,
            file_info_href => $file_info_href,
            parameter_href => $parameter_href,
            recipe_name    => $recipe_name,
            stream         => q{in},
            temp_directory => $temp_directory,
        }
    );
    my $indir_path_prefix       = $io{in}{dir_path_prefix};
    my $infile_suffix           = $io{in}{file_suffix};
    my $infile_name_prefix      = $io{in}{file_name_prefix};
    my $temp_infile_name_prefix = $io{temp}{file_name_prefix};
    my %temp_infile_path        = %{ $io{temp}{file_path_href} };

    my %rec_atr = get_recipe_attributes(
        {
            parameter_href => $parameter_href,
            recipe_name    => $recipe_name,
        }
    );
    my $job_id_chain       = $rec_atr{chain};
    my $recipe_mode        = $active_parameter_href->{$recipe_name};
    my $referencefile_path = $active_parameter_href->{human_genome_reference};
    my $analysis_type      = $active_parameter_href->{analysis_type}{$sample_id};
    my $xargs_file_path_prefix;
    my ( $core_number, $time, @source_environment_cmds ) = get_recipe_parameters(
        {
            active_parameter_href => $active_parameter_href,
            recipe_name           => $recipe_name,
        }
    );

    ## Add merged infile name prefix after merging all BAM files per sample_id
    my $merged_infile_prefix = get_merged_infile_prefix(
        {
            file_info_href => $file_info_href,
            sample_id      => $sample_id,
        }
    );

    ## Outpaths
    ## Assign suffix
    my $outfile_suffix = $rec_atr{outfile_suffix};
    my $outsample_directory =
      catdir( $active_parameter_href->{outdata_dir}, $sample_id, $recipe_name );
    my $outfile_tag =
      $file_info_href->{$sample_id}{$recipe_name}{file_tag};
    my @outfile_paths =
      map {
        catdir( $outsample_directory,
            $merged_infile_prefix . $outfile_tag . $DOT . $_ . $outfile_suffix )
      } @{ $file_info_href->{contigs_size_ordered} };

    ## Set and get the io files per chain, id and stream
    %io = (
        %io,
        parse_io_outfiles(
            {
                chain_id       => $job_id_chain,
                id             => $sample_id,
                file_info_href => $file_info_href,
                file_paths_ref => \@outfile_paths,
                parameter_href => $parameter_href,
                recipe_name    => $recipe_name,
                temp_directory => $temp_directory,
            }
        )
    );

    my $outdir_path_prefix       = $io{out}{dir_path_prefix};
    my $outfile_name_prefix      = $io{out}{file_name_prefix};
    my $temp_outfile_path_prefix = $io{temp}{file_path_prefix};
    my %temp_outfile_path        = %{ $io{temp}{file_path_href} };

    ## Filehandles
    # Create anonymous filehandle
    my $XARGSFILEHANDLE = IO::Handle->new();

    ### SHELL:

    ## Generate gatk intervals. Chromosomes for WGS/WTS and paths to contig_bed_files for WES
    my %gatk_intervals = get_gatk_intervals(
        {
            analysis_type         => $analysis_type,
            contigs_ref           => \@{ $file_info_href->{contigs_size_ordered} },
            exome_target_bed_href => $active_parameter_href->{exome_target_bed},
            FILEHANDLE            => $FILEHANDLE,
            file_ending           => $file_info_href->{exome_target_bed}[0],
            max_cores_per_node    => $core_number,
            log                   => $log,
            outdirectory          => $temp_directory,
            reference_dir         => $active_parameter_href->{reference_dir},
            sample_id             => $sample_id,
        }
    );

    Readonly my $JAVA_MEMORY_ALLOCATION => 6;

    # Constrain parallelization to match available memory
    my $program_core_number = get_memory_constrained_core_number(
        {
            max_cores_per_node => $active_parameter_href->{max_cores_per_node},
            memory_allocation  => $JAVA_MEMORY_ALLOCATION,
            node_ram_memory    => $active_parameter_href->{node_ram_memory},
            recipe_core_number => $core_number,
        }
    );

    ## GATK BaseRecalibrator
    say {$FILEHANDLE} q{## GATK BaseRecalibrator};

    ## Create file commands for xargs
    ( $xargs_file_counter, $xargs_file_path_prefix ) = xargs_command(
        {
            core_number        => $program_core_number,
            FILEHANDLE         => $FILEHANDLE,
            file_path          => $file_path,
            recipe_info_path   => $recipe_info_path,
            XARGSFILEHANDLE    => $XARGSFILEHANDLE,
            xargs_file_counter => $xargs_file_counter,
        }
    );

    my @base_quality_score_recalibration_files;
  CONTIG:
    foreach my $contig ( @{ $file_info_href->{contigs_size_ordered} } ) {

        my $base_quality_score_recalibration_file =
          $temp_outfile_path_prefix . $DOT . $contig . $DOT . q{grp};
## Add for gathering base recal files later
        push @base_quality_score_recalibration_files,
          $base_quality_score_recalibration_file;
        my $stderrfile_path =
          $xargs_file_path_prefix . $DOT . $contig . $DOT . q{stderr.txt};
        gatk_baserecalibrator(
            {
                FILEHANDLE           => $XARGSFILEHANDLE,
                infile_path          => $temp_infile_path{$contig},
                intervals_ref        => $gatk_intervals{$contig},
                java_use_large_pages => $active_parameter_href->{java_use_large_pages},
                memory_allocation    => q{Xmx} . $JAVA_MEMORY_ALLOCATION . q{g},
                known_sites_ref =>
                  \@{ $active_parameter_href->{gatk_baserecalibration_known_sites} },
                verbosity          => $active_parameter_href->{gatk_logging_level},
                outfile_path       => $base_quality_score_recalibration_file,
                referencefile_path => $referencefile_path,
                stderrfile_path    => $stderrfile_path,
                temp_directory     => $temp_directory,
                xargs_mode         => 1,
            }
        );
        say {$XARGSFILEHANDLE} $NEWLINE;
    }

    ## GATK GatherBQSRReports
    say {$FILEHANDLE} q{## GATK GatherBQSRReports};
    my $gatk_gatherbqsr_outfile_path =
      $temp_outfile_path_prefix . $DOT . $sample_id . $DOT . q{grp};
    gatk_gatherbqsrreports(
        {
            base_quality_score_recalibration_files_ref =>
              \@base_quality_score_recalibration_files,
            FILEHANDLE   => $FILEHANDLE,
            outfile_path => $gatk_gatherbqsr_outfile_path,
        }
    );
    say {$FILEHANDLE} $NEWLINE;

    ## GATK ApplyBQSR
    say {$FILEHANDLE} q{## GATK ApplyBQSR};

    ## Create file commands for xargs
    ( $xargs_file_counter, $xargs_file_path_prefix ) = xargs_command(
        {
            core_number        => $program_core_number,
            FILEHANDLE         => $FILEHANDLE,
            file_path          => $file_path,
            recipe_info_path   => $recipe_info_path,
            XARGSFILEHANDLE    => $XARGSFILEHANDLE,
            xargs_file_counter => $xargs_file_counter,
        }
    );

  CONTIG:
    foreach my $contig ( @{ $file_info_href->{contigs_size_ordered} } ) {

        my $stderrfile_path =
          $xargs_file_path_prefix . $DOT . $contig . $DOT . q{stderr.txt};
        gatk_applybqsr(
            {
                base_quality_score_recalibration_file => $gatk_gatherbqsr_outfile_path,
                FILEHANDLE                            => $XARGSFILEHANDLE,
                infile_path                           => $temp_infile_path{$contig},
                intervals_ref                         => $gatk_intervals{$contig},
                java_use_large_pages => $active_parameter_href->{java_use_large_pages},
                memory_allocation    => q{Xmx} . $JAVA_MEMORY_ALLOCATION . q{g},
                verbosity            => $active_parameter_href->{gatk_logging_level},
                read_filters_ref =>
                  \@{ $active_parameter_href->{gatk_baserecalibration_read_filters} },
                static_quantized_quals_ref => \@{
                    $active_parameter_href
                      ->{gatk_baserecalibration_static_quantized_quals}
                },
                outfile_path       => $temp_outfile_path{$contig},
                referencefile_path => $referencefile_path,
                stderrfile_path    => $stderrfile_path,
                temp_directory     => $temp_directory,
                xargs_mode         => 1,
            }
        );
        say {$XARGSFILEHANDLE} $NEWLINE;
    }

    ## Copies file from temporary directory. Per contig for variant callers.
    say {$FILEHANDLE} q{## Copy file from temporary directory};
    ($xargs_file_counter) = xargs_migrate_contig_files(
        {
            contigs_ref        => \@{ $file_info_href->{contigs_size_ordered} },
            FILEHANDLE         => $FILEHANDLE,
            file_ending        => substr( $outfile_suffix, 0, 2 ) . $ASTERISK,
            file_path          => $file_path,
            core_number        => $core_number,
            outdirectory       => $outdir_path_prefix,
            outfile            => $outfile_name_prefix,
            recipe_info_path   => $recipe_info_path,
            temp_directory     => $temp_directory,
            XARGSFILEHANDLE    => $XARGSFILEHANDLE,
            xargs_file_counter => $xargs_file_counter,
        }
    );

    ## Remove file at temporary directory
    delete_contig_files(
        {
            core_number       => $core_number,
            FILEHANDLE        => $FILEHANDLE,
            file_elements_ref => \@{ $file_info_href->{contigs_size_ordered} },
            file_ending       => substr( $infile_suffix, 0, 2 ) . $ASTERISK,
            file_name         => $temp_infile_name_prefix,
            indirectory       => $temp_directory,
        }
    );

    ## Gather BAM files
    say {$FILEHANDLE} q{## Gather BAM files};

    ## Assemble infile paths in contig order and not per size
    my @gather_infile_paths =
      map { $temp_outfile_path{$_} } @{ $file_info_href->{contigs} };

    picardtools_gatherbamfiles(
        {
            create_index     => q{true},
            FILEHANDLE       => $FILEHANDLE,
            infile_paths_ref => \@gather_infile_paths,
            java_jar =>
              catfile( $active_parameter_href->{picardtools_path}, q{picard.jar} ),
            java_use_large_pages => $active_parameter_href->{java_use_large_pages},
            memory_allocation    => q{Xmx4g},
            outfile_path         => $temp_outfile_path_prefix . $outfile_suffix,
            referencefile_path   => $referencefile_path,
            temp_directory       => $temp_directory,
        }
    );
    say {$FILEHANDLE} $NEWLINE;

    ## Copies file from temporary directory.
    say {$FILEHANDLE} q{## Copy file from temporary directory};
    migrate_file(
        {
            FILEHANDLE  => $FILEHANDLE,
            infile_path => $temp_outfile_path_prefix
              . substr( $outfile_suffix, 0, 2 )
              . $ASTERISK,
            outfile_path => $outdir_path_prefix,
        }
    );
    say {$FILEHANDLE} q{wait}, $NEWLINE;

    close $XARGSFILEHANDLE;
    close $FILEHANDLE;

    if ( $recipe_mode == 1 ) {

        my $gathered_outfile_path =
          catfile( $outdir_path_prefix, $outfile_name_prefix . $outfile_suffix );

        ## Collect QC metadata info for later use
        set_recipe_outfile_in_sample_info(
            {
                infile           => $outfile_name_prefix,
                path             => $gathered_outfile_path,
                recipe_name      => q{gatk_baserecalibration},
                sample_id        => $sample_id,
                sample_info_href => $sample_info_href,
            }
        );
        my $most_complete_format_key =
          q{most_complete} . $UNDERSCORE . substr $outfile_suffix, 1;
        set_processing_metafile_in_sample_info(
            {
                metafile_tag     => $most_complete_format_key,
                path             => $gathered_outfile_path,
                sample_id        => $sample_id,
                sample_info_href => $sample_info_href,
            }
        );

        submit_recipe(
            {
                base_command            => $profile_base_command,
                case_id                 => $case_id,
                dependency_method       => q{sample_to_sample},
                infile_lane_prefix_href => $infile_lane_prefix_href,
                job_id_chain            => $job_id_chain,
                job_id_href             => $job_id_href,
                log                     => $log,
                recipe_file_path        => $file_path,
                sample_id               => $sample_id,
                submission_profile      => $active_parameter_href->{submission_profile},
            }
        );
    }
    return 1;
}

1;
