package MIP::Recipes::Analysis::Cadd;

use 5.026;
use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
use File::Basename qw{ dirname };
use File::Spec::Functions qw{ catdir catfile devnull };
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
    our @EXPORT_OK = qw{ analysis_cadd };

}

## Constants
Readonly my $COMMA         => q{,};
Readonly my $DOT           => q{.};
Readonly my $NEWLINE       => qq{\n};
Readonly my $REGION_START  => q{2};
Readonly my $REGION_END    => q{2};
Readonly my $SEQUENCE_NAME => q{1};
Readonly my $SPACE         => q{ };
Readonly my $SEMICOLON     => q{;};
Readonly my $UNDERSCORE    => q{_};

sub analysis_cadd {

## Function : Annotate variants with CADD score
## Returns  :
## Arguments: $active_parameter_href   => Active parameters for this analysis hash {REF}
##          : $case_id                 => Family id
##          : $file_info_href          => File_info hash {REF}
##          : $infile_lane_prefix_href => Infile(s) without the ".ending" {REF}
##          : $job_id_href             => Job id hash {REF}
##          : $parameter_href          => Parameter hash {REF}
##          : $profile_base_command    => Submission profile base command
##          : $recipe_name             => Recipe name
##          : $sample_info_href        => Info on samples and case hash {REF}

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $active_parameter_href;
    my $file_info_href;
    my $infile_lane_prefix_href;
    my $job_id_href;
    my $parameter_href;
    my $profile_base_command;
    my $recipe_name;
    my $sample_info_href;

    ## Default(s)
    my $case_id;

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

    use MIP::Cluster qw{ get_core_number };
    use MIP::Get::File qw{ get_io_files };
    use MIP::Get::Parameter qw{ get_recipe_parameters get_recipe_attributes };
    use MIP::Parse::File qw{ parse_io_outfiles };
    use MIP::Program::Variantcalling::Bcftools qw{ bcftools_annotate bcftools_view };
    use MIP::Program::Variantcalling::Cadd qw{ cadd };
    use MIP::Program::Utility::Htslib qw{ htslib_tabix };
    use MIP::Processmanagement::Processes qw{ submit_recipe };
    use MIP::QC::Sample_info qw{ set_recipe_outfile_in_sample_info };
    use MIP::Recipes::Analysis::Xargs qw{ xargs_command };
    use MIP::Script::Setup_script qw{ setup_script };

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
        }
    );
    my $infile_name_prefix = $io{in}{file_name_prefix};
    my %infile_path        = %{ $io{in}{file_path_href} };

    my $assembly_version = $file_info_href->{human_genome_reference_source}
      . $file_info_href->{human_genome_reference_version};
    my $cadd_columns_name = join $COMMA, @{ $active_parameter_href->{cadd_column_names} };
    my @contigs_size_ordered = @{ $file_info_href->{contigs_size_ordered} };
    my $job_id_chain         = get_recipe_attributes(
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

    ## Set and get the io files per chain, id and stream
    %io = (
        %io,
        parse_io_outfiles(
            {
                chain_id         => $job_id_chain,
                id               => $case_id,
                file_info_href   => $file_info_href,
                file_name_prefix => $infile_name_prefix,
                iterators_ref    => \@contigs_size_ordered,
                outdata_dir      => $active_parameter_href->{outdata_dir},
                parameter_href   => $parameter_href,
                recipe_name      => $recipe_name,
            }
        )
    );

    my @outfile_paths       = @{ $io{out}{file_paths} };
    my $outfile_path_prefix = $io{out}{file_path_prefix};
    my %outfile_path        = %{ $io{out}{file_path_href} };
    my $outfile_suffix      = $io{out}{file_suffix};

    ## Filehandles
    # Create anonymous filehandle
    my $FILEHANDLE      = IO::Handle->new();
    my $XARGSFILEHANDLE = IO::Handle->new();

    ## Get core number depending on user supplied input exists or not and max number of cores
    $core_number = get_core_number(
        {
            max_cores_per_node   => $active_parameter_href->{max_cores_per_node},
            modifier_core_number => scalar keys %infile_path,
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
        }
    );

    ### SHELL:

    say {$FILEHANDLE} q{## } . $recipe_name;

    ## View indels and calculate CADD
    say {$FILEHANDLE} q{## CADD};

    ## Create file commands for xargs
    my ( $xargs_file_counter, $xargs_file_path_prefix ) = xargs_command(
        {
            core_number      => $core_number,
            FILEHANDLE       => $FILEHANDLE,
            file_path        => $recipe_file_path,
            recipe_info_path => $recipe_info_path,
            XARGSFILEHANDLE  => $XARGSFILEHANDLE,
        }
    );

    ## Process per contig
  CONTIG:
    foreach my $contig (@contigs_size_ordered) {

        ## Get parameters
        my $cadd_outfile_path = $outfile_path_prefix . $DOT . $contig . $DOT . q{tsv.gz};
        my $stderrfile_path =
          $xargs_file_path_prefix . $DOT . $contig . $DOT . q{stderr.txt};
        my $view_outfile_path =
          $outfile_path_prefix . $UNDERSCORE . q{view} . $DOT . $contig . $outfile_suffix;

        bcftools_view(
            {
                FILEHANDLE      => $XARGSFILEHANDLE,
                infile_path     => $infile_path{$contig},
                types           => q{indels},
                outfile_path    => $view_outfile_path,
                output_type     => q{v},
                stderrfile_path => $stderrfile_path,
            }
        );
        print {$XARGSFILEHANDLE} $SEMICOLON . $SPACE;

        cadd(
            {
                FILEHANDLE             => $XARGSFILEHANDLE,
                genome_build           => $assembly_version,
                infile_path            => $view_outfile_path,
                outfile_path           => $cadd_outfile_path,
                stderrfile_path_append => $stderrfile_path,
            }
        );
        say {$XARGSFILEHANDLE} $NEWLINE;
    }

    ### Annotate
    ## Tabix cadd outfile and annotate original vcf file with indel CADD score
    say {$FILEHANDLE} q{## Tabix and bcftools annotate};

    ## Create file commands for xargs
    ( $xargs_file_counter, $xargs_file_path_prefix ) = xargs_command(
        {
            core_number        => $core_number,
            FILEHANDLE         => $FILEHANDLE,
            file_path          => $recipe_file_path,
            recipe_info_path   => $recipe_info_path,
            XARGSFILEHANDLE    => $XARGSFILEHANDLE,
            xargs_file_counter => $xargs_file_counter,
        }
    );

    ## Process per contig
  CONTIG:
    foreach my $contig (@contigs_size_ordered) {

        ## Get parameters
        my $stderrfile_path =
          $xargs_file_path_prefix . $DOT . $contig . $DOT . q{stderr.txt};

        # Corresponds to cadd outfile path
        my $tabix_infile_path = $outfile_path_prefix . $DOT . $contig . $DOT . q{tsv.gz};

        ## Create tabix index
        htslib_tabix(
            {
                begin           => $REGION_START,
                end             => $REGION_END,
                FILEHANDLE      => $XARGSFILEHANDLE,
                force           => 1,
                infile_path     => $tabix_infile_path,
                sequence        => $SEQUENCE_NAME,
                stderrfile_path => $stderrfile_path,
            }
        );
        print {$XARGSFILEHANDLE} $SEMICOLON . $SPACE;

        bcftools_annotate(
            {
                annotations_file_path  => $tabix_infile_path,
                columns_name           => $cadd_columns_name,
                FILEHANDLE             => $XARGSFILEHANDLE,
                headerfile_path        => $active_parameter_href->{cadd_vcf_header_file},
                infile_path            => $infile_path{$contig},
                outfile_path           => $outfile_path{$contig},
                output_type            => q{v},
                stderrfile_path_append => $stderrfile_path,
            }
        );
        say {$XARGSFILEHANDLE} $NEWLINE;
    }

    ## Close FILEHANDLES
    close $FILEHANDLE or $log->logcroak(q{Could not close FILEHANDLE});
    close $XARGSFILEHANDLE
      or $log->logcroak(q{Could not close XARGSFILEHANDLE});

    if ( $recipe_mode == 1 ) {

        ## Collect QC metadata info for later use
        set_recipe_outfile_in_sample_info(
            {
                path             => $outfile_paths[0],
                recipe_name      => $recipe_name,
                sample_info_href => $sample_info_href,
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
