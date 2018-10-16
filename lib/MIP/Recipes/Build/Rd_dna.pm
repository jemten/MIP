package MIP::Recipes::Build::Rd_dna;

use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
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
    our $VERSION = 1.01;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw{ build_rd_dna_meta_files };
}

## Constants
Readonly my $SPACE     => q{ };
Readonly my $EMPTY_STR => q{};
Readonly my $TAB       => qq{\t};

sub build_rd_dna_meta_files {

## Function : Rare disease DNA pipeline recipe for wes/wgs data analysis.
## Returns  :
## Arguments: $active_parameter_href   => Active parameters for this analysis hash {REF}
##          : $file_info_href          => File info hash {REF}
##          : $infile_lane_prefix_href => Infile(s) without the ".ending" {REF}
##          : $job_id_href             => Job id hash {REF}
##          : $log                     => Log object to write to
##          : $parameter_href          => Parameter hash {REF}
##          : $sample_info_href        => Info on samples and family hash {REF}

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $active_parameter_href;
    my $file_info_href;
    my $infile_lane_prefix_href;
    my $job_id_href;
    my $log;
    my $parameter_href;
    my $sample_info_href;

    my $tmpl = {
        active_parameter_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$active_parameter_href,
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
        log => {
            defined  => 1,
            required => 1,
            store    => \$log,
        },
        parameter_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$parameter_href,
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

    use MIP::Check::Reference qw{
      check_references_for_vt };
    use MIP::Recipes::Analysis::Vt_core qw{ analysis_vt_core };
    use MIP::Recipes::Build::Bwa_prerequisites qw{ build_bwa_prerequisites };
    use MIP::Recipes::Build::Capture_file_prerequisites
      qw{ build_capture_file_prerequisites };
    use MIP::Recipes::Build::Human_genome_prerequisites
      qw{ build_human_genome_prerequisites };
    use MIP::Recipes::Build::Rtg_prerequisites qw{ build_rtg_prerequisites };

    my %build_recipe = (
        bwa_build_reference => \&build_bwa_prerequisites,
        exome_target_bed    => \&build_capture_file_prerequisites,
        human_genome_reference_file_endings =>
          \&build_human_genome_prerequisites,
        rtg_vcfeval_reference_genome => \&build_rtg_prerequisites,
    );

  BUILD_RECIPE:
    foreach my $parameter_build_name ( keys %build_recipe ) {

      PROGRAM:
        foreach my $program (
            @{ $parameter_href->{$parameter_build_name}{associated_program} } )
        {

            next PROGRAM if ( not $active_parameter_href->{$program} );

            next BUILD_RECIPE
              if (
                not $parameter_href->{$parameter_build_name}{build_file} == 1 );

            $build_recipe{$parameter_build_name}->(
                {
                    active_parameter_href   => $active_parameter_href,
                    file_info_href          => $file_info_href,
                    infile_lane_prefix_href => $infile_lane_prefix_href,
                    job_id_href             => $job_id_href,
                    log                     => $log,
                    parameter_build_suffixes_ref =>
                      \@{ $file_info_href->{$parameter_build_name} },
                    parameter_href   => $parameter_href,
                    program_name     => $program,
                    sample_info_href => $sample_info_href,
                }
            );

            ## Build once for all associated programs
            $parameter_href->{$parameter_build_name}{build_file} = 0;
        }
    }

    $log->info( $TAB . q{Reference check: Reference prerequisites checked} );

## Check if vt has processed references, if not try to reprocesses them before launcing modules
    $log->info(q{[Reference check - Reference processed by VT]});
    if (   $active_parameter_href->{vt_decompose}
        || $active_parameter_href->{vt_normalize} )
    {

        my @to_process_references = check_references_for_vt(
            {
                active_parameter_href => $active_parameter_href,
                log                   => $log,
                parameter_href        => $parameter_href,
                vt_references_ref =>
                  \@{ $active_parameter_href->{decompose_normalize_references}
                  },
            }
        );

      REFERENCE:
        foreach my $reference_file_path (@to_process_references) {

            $log->info(q{[VT - Normalize and decompose]});
            $log->info( $TAB . q{File: } . $reference_file_path );

            ## Split multi allelic records into single records and normalize
            analysis_vt_core(
                {
                    active_parameter_href   => $active_parameter_href,
                    decompose               => 1,
                    infile_lane_prefix_href => $infile_lane_prefix_href,
                    job_id_href             => $job_id_href,
                    infile_path             => $reference_file_path,
                    normalize               => 1,
                    parameter_href          => $parameter_href,
                    program_directory       => q{vt},
                }
            );
        }
    }
    return;
}

1;