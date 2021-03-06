package MIP::Recipes::Analysis::Multiqc;

use 5.026;
use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
use File::Spec::Functions qw{ catdir catfile };
use Params::Check qw{ check allow last_error };
use open qw{ :encoding(UTF-8) :std };
use strict;
use utf8;
use warnings;
use warnings qw{ FATAL utf8 };

## CPANM
use autodie qw{ :all };
use Readonly;

## MIPs lib/
use MIP::Constants qw{ $NEWLINE };

BEGIN {

    require Exporter;
    use base qw{ Exporter };

    # Set the version for version checking
    our $VERSION = 1.06;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw{ analysis_multiqc };

}

sub analysis_multiqc {

## Function : Aggregate bioinforamtics reports per case
## Returns  :
## Arguments: $active_parameter_href   => Active parameters for this analysis hash {REF}
##          : $case_id                 => Family id
##          : $file_info_href          => File info hash {REF}
##          : $infile_lane_prefix_href => Infile(s) without the ".ending" {REF}
##          : $job_id_href             => Job id hash {REF}
##          : $parameter_href          => Parameter hash {REF}
##          : $profile_base_command    => Submission profile base command
##          : $recipe_name             => Program name
##          : $sample_info_href        => Info on samples and case hash {REF}

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
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    use MIP::Get::Parameter qw{ get_recipe_parameters get_recipe_attributes };
    use MIP::Parse::File qw{ parse_io_outfiles };
    use MIP::Processmanagement::Processes qw{ submit_recipe };
    use MIP::Program::Qc::Multiqc qw{ multiqc };
    use MIP::Script::Setup_script qw{ setup_script };
    use MIP::QC::Sample_info qw{ set_recipe_metafile_in_sample_info };

    ### PREPROCESSING:

    ## Retrieve logger object
    my $log = Log::Log4perl->get_logger(q{MIP});

    ## Unpack parameters
    my $job_id_chain = get_recipe_attributes(
        {
            parameter_href => $parameter_href,
            recipe_name    => $recipe_name,
            attribute      => q{chain},
        }
    );
    my $recipe_mode = $active_parameter_href->{$recipe_name};
    my ( $core_number, $time, @source_environment_cmds ) = get_recipe_parameters(
        {
            active_parameter_href => $active_parameter_href,
            recipe_name           => $recipe_name,
        }
    );

    ## Filehandles
    # Create anonymous filehandle
    my $FILEHANDLE = IO::Handle->new();

    ## Creates recipe directories (info & data & script), recipe script filenames and writes sbatch header
    my ($recipe_file_path) = setup_script(
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

    say {$FILEHANDLE} q{## Multiqc};

    ## Always analyse case
    my @report_ids = ($case_id);

    ## Generate report per sample id
    if ( $active_parameter_href->{multiqc_per_sample} ) {

        ## Add samples to analysis
        push @report_ids, @{ $active_parameter_href->{sample_ids} };
    }

    my $indir_path = $active_parameter_href->{outdata_dir};

  REPORT_ID:
    foreach my $report_id (@report_ids) {

        ## Assign directories
        my $outdir_path =
          catdir( $active_parameter_href->{outdata_dir}, $report_id, $recipe_name );

        ## Analyse sample id only for this report
        if ( $report_id ne $case_id ) {

            $indir_path = catdir( $active_parameter_href->{outdata_dir}, $report_id );
        }

        multiqc(
            {
                FILEHANDLE  => $FILEHANDLE,
                force       => 1,
                indir_path  => $indir_path,
                outdir_path => $outdir_path,
            }
        );
        say {$FILEHANDLE} $NEWLINE;

        if ( $recipe_mode == 1 ) {

            ## Collect QC metadata info for later use
            set_recipe_metafile_in_sample_info(
                {
                    metafile_tag     => $report_id,
                    path             => catfile( $outdir_path, q{multiqc_report.html} ),
                    recipe_name      => q{multiqc},
                    sample_info_href => $sample_info_href,
                }
            );
        }
    }
    close $FILEHANDLE;

    if ( $recipe_mode == 1 ) {

        submit_recipe(
            {
                base_command        => $profile_base_command,
                dependency_method   => q{add_to_all},
                job_dependency_type => q{afterok},
                job_id_href         => $job_id_href,
                log                 => $log,
                job_id_chain        => $job_id_chain,
                recipe_file_path    => $recipe_file_path,
                submission_profile  => $active_parameter_href->{submission_profile},
            }
        );
    }
    return 1;
}

1;
