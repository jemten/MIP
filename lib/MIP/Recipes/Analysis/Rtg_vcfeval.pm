package MIP::Recipes::Analysis::Rtg_vcfeval;

use 5.026;
use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
use File::Spec::Functions qw{ catdir catfile };
use open qw{ :encoding(UTF-8) :std };
use Params::Check qw{ allow check last_error };
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
    our $VERSION = 1.04;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw{ analysis_rtg_vcfeval };

}

## Constants
Readonly my $DOT        => q{.};
Readonly my $NEWLINE    => qq{\n};
Readonly my $UNDERSCORE => q{_};

sub analysis_rtg_vcfeval {

## Function : Evaluation of vcf variants using rtg
## Returns  :
## Arguments: $active_parameter_href   => Active parameters for this analysis hash {REF}
##          : $case_id                 => Family id
##          : $file_info_href          => File_info hash {REF}
##          : $infile_lane_prefix_href => Infile(s) without the ".ending" {REF}
##          : $job_id_href             => Job id hash {REF}
##          : $parameter_href          => Parameter hash {REF}
##          : $recipe_name             => Program name
##          : $sample_id               => Sample id
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
    my $sample_id;
    my $sample_info_href;

    ## Default(s)
    my $case_id;
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
        recipe_name => {
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
            strict_type => 1,
            store       => \$temp_directory,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    use MIP::Get::File qw{ get_io_files };
    use MIP::Get::Parameter qw{ get_recipe_parameters get_recipe_attributes };
    use MIP::Gnu::Coreutils qw{ gnu_rm  };
    use MIP::Parse::File qw{ parse_io_outfiles };
    use MIP::Program::Qc::Rtg qw{ rtg_vcfeval };
    use MIP::Program::Variantcalling::Bcftools
      qw{ bcftools_rename_vcf_samples bcftools_view_and_index_vcf };
    use MIP::Processmanagement::Processes qw{ submit_recipe };
    use MIP::QC::Sample_info qw{ set_recipe_outfile_in_sample_info };
    use MIP::Script::Setup_script qw{ setup_script };

    ## Return if not a nist_id sample
    return if ( not exists $active_parameter_href->{nist_id}{$sample_id} );

    ### PREPROCESSING:

    ## Retrieve logger object
    my $log = Log::Log4perl->get_logger(q{MIP});

    ## Unpack parameters
    ## Get the io infiles per chain and id
    my %io = get_io_files(
        {
            id             => $case_id,
            file_info_href => $file_info_href,
            parameter_href => $parameter_href,
            recipe_name    => $recipe_name,
            stream         => q{in},
            temp_directory => $temp_directory,
        }
    );
    my $infile_name_prefix = $io{in}{file_name_prefix};
    my $infile_path        = $io{in}{file_path};

    my $job_id_chain = get_recipe_attributes(
        {
            parameter_href => $parameter_href,
            recipe_name    => $recipe_name,
            attribute      => q{chain},
        }
    );
    my $nist_id       = $active_parameter_href->{nist_id}{$sample_id};
    my @nist_versions = @{ $active_parameter_href->{nist_versions} };
    my $recipe_mode   = $active_parameter_href->{$recipe_name};
    my ( $core_number, $time, @source_environment_cmds ) = get_recipe_parameters(
        {
            active_parameter_href => $active_parameter_href,
            recipe_name           => $recipe_name,
        }
    );

    ## Set and get the io files per chain, id and stream
    %io = (
        %io,
        parse_io_outfiles(
            {
                chain_id         => $job_id_chain,
                id               => $case_id,
                file_info_href   => $file_info_href,
                file_name_prefix => $infile_name_prefix,
                iterators_ref    => [$nist_id],
                outdata_dir      => $active_parameter_href->{outdata_dir},
                parameter_href   => $parameter_href,
                recipe_name      => $recipe_name,
                temp_directory   => $temp_directory,
            }
        )
    );

    my $outdir_path_prefix  = $io{out}{dir_path_prefix};
    my $outfile_path_prefix = $io{out}{file_path_prefix};

    ## Filehandles
    # Create anonymous filehandle
    my $FILEHANDLE = IO::Handle->new();

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
        }
    );

    ### SHELL:
    my $rtg_outdirectory_path = catfile( $outdir_path_prefix, $sample_id );

  NIST_VERSION:
    foreach my $nist_version (@nist_versions) {

        ## Skip this nist version if no supported nist_id
        next NIST_VERSION
          if (
            not
            exists $active_parameter_href->{nist_call_set_vcf}{$nist_version}{$nist_id} );

        say {$FILEHANDLE} q{### Processing NIST ID: }
          . $nist_id
          . q{ reference version: }
          . $nist_version;

        my $nist_file_path =
          catfile( $temp_directory, q{nist} . $UNDERSCORE . $nist_version );
        my $nist_vcf_file_path =
          $active_parameter_href->{nist_call_set_vcf}{$nist_version}{$nist_id};
        my $nist_bed_file_path =
          $active_parameter_href->{nist_call_set_bed}{$nist_version}{$nist_id};

        say {$FILEHANDLE} q{## Adding sample name to baseline calls};
        bcftools_rename_vcf_samples(
            {
                FILEHANDLE          => $FILEHANDLE,
                index               => 1,
                index_type          => q{tbi},
                infile              => $nist_vcf_file_path,
                outfile_path_prefix => $nist_file_path . $UNDERSCORE . q{refrm},
                output_type         => q{z},
                temp_directory      => $temp_directory,
                sample_ids_ref      => [$sample_id],
            }
        );

        say {$FILEHANDLE} q{## Compressing and indexing sample calls};
        bcftools_view_and_index_vcf(
            {
                FILEHANDLE          => $FILEHANDLE,
                index               => 1,
                index_type          => q{tbi},
                infile_path         => $infile_path,
                outfile_path_prefix => $outfile_path_prefix,
                output_type         => q{z},
            }
        );

        say {$FILEHANDLE} q{## Remove potential old Rtg vcfeval outdir};
        my $nist_version_rtg_outdirectory_path =
          catfile( $outdir_path_prefix, $sample_id, $nist_version );
        gnu_rm(
            {
                FILEHANDLE  => $FILEHANDLE,
                force       => 1,
                infile_path => $nist_version_rtg_outdirectory_path,
                recursive   => 1,
            }
        );
        say {$FILEHANDLE} $NEWLINE;

        say {$FILEHANDLE} q{## Rtg vcfeval};
        rtg_vcfeval(
            {
                baselinefile_path     => $nist_file_path . $UNDERSCORE . q{refrm.vcf.gz},
                callfile_path         => $outfile_path_prefix . $DOT . q{vcf.gz},
                eval_region_file_path => $nist_bed_file_path,
                FILEHANDLE            => $FILEHANDLE,
                outputdirectory_path  => $nist_version_rtg_outdirectory_path,
                sample_id             => $sample_id,
                sdf_template_file_path =>
                  $active_parameter_href->{rtg_vcfeval_reference_genome}
                  . $file_info_href->{rtg_vcfeval_reference_genome}[0]
                ,    # Only one directory for sdf
            }
        );

        say {$FILEHANDLE} $NEWLINE;
    }

    ## Close FILEHANDLE
    close $FILEHANDLE or $log->logcroak(q{Could not close FILEHANDLE});

    if ( $recipe_mode == 1 ) {

## Collect QC metadata info for later use
        set_recipe_outfile_in_sample_info(
            {
                outdirectory     => $rtg_outdirectory_path,
                recipe_name      => $recipe_name,
                sample_info_href => $sample_info_href,
            }
        );

        submit_recipe(
            {
                dependency_method       => q{case_to_island},
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
    return;
}

1;
