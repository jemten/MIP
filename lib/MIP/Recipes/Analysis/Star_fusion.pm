package MIP::Recipes::Analysis::Star_fusion;

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
    our $VERSION = 1.08;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw{ analysis_star_fusion };

}

## Constants
Readonly my $ASTERISK => q{*};
Readonly my $NEWLINE  => qq{\n};

sub analysis_star_fusion {

## Function : Analysis recipe for star-fusion v1.4.0
## Returns  :
## Arguments: $active_parameter_href   => Active parameters for this analysis hash {REF}
##          : $case_id               => Family id
##          : $file_info_href          => File_info hash {REF}
##          : $infile_lane_prefix_href => Infile(s) without the ".ending" {REF}
##          : $job_id_href             => Job id hash {REF}
##          : $parameter_href          => Parameter hash {REF}
##          : $recipe_name            => Program name
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
            store       => \$temp_directory,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    use MIP::File::Format::Star_fusion qw{ create_star_fusion_sample_file };
    use MIP::Get::File qw{ get_io_files };
    use MIP::Get::Parameter qw{ get_recipe_parameters get_recipe_attributes };
    use MIP::Gnu::Coreutils qw{ gnu_cp };
    use MIP::Parse::File qw{ parse_io_outfiles };
    use MIP::Program::Variantcalling::Star_fusion qw{ star_fusion };
    use MIP::Processmanagement::Processes qw{ submit_recipe };
    use MIP::QC::Sample_info qw{ set_recipe_outfile_in_sample_info };
    use MIP::Script::Setup_script qw{ setup_script };

    ## PREPROCESSING:

    ## Star fusion has a fixed sample_prefix
    Readonly my $STAR_FUSION_PREFIX => q{star-fusion.fusion_predictions};

    ## Retrieve logger object
    my $log = Log::Log4perl->get_logger(q{MIP});

    ## Unpack parameters
    ## Get the io infiles per chain and id
    my %io = get_io_files(
        {
            file_info_href => $file_info_href,
            id             => $sample_id,
            parameter_href => $parameter_href,
            recipe_name    => $recipe_name,
            stream         => q{in},
            temp_directory => $temp_directory,
        }
    );
    my $indir_path        = $io{in}{dir_path};
    my @temp_infile_paths = @{ $io{temp}{file_paths} };

    ## Build outfile_paths
    my %recipe_attribute = get_recipe_attributes(
        {
            parameter_href => $parameter_href,
            recipe_name    => $recipe_name,
        }
    );
    my $outdir_path =
      catdir( $active_parameter_href->{outdata_dir}, $sample_id, $recipe_name );
    my $outsample_name = $STAR_FUSION_PREFIX . $recipe_attribute{outfile_suffix};
    my @file_paths     = catfile( $outdir_path, $outsample_name );
    my $recipe_mode    = $active_parameter_href->{$recipe_name};
    my ( $core_number, $time, @source_environment_cmds ) = get_recipe_parameters(
        {
            active_parameter_href => $active_parameter_href,
            recipe_name           => $recipe_name,
        }
    );

    %io = (
        %io,
        parse_io_outfiles(
            {
                chain_id       => $recipe_attribute{chain},
                id             => $sample_id,
                file_info_href => $file_info_href,
                file_paths_ref => \@file_paths,
                parameter_href => $parameter_href,
                recipe_name    => $recipe_name,
            }
        )
    );

    ## Filehandles
    # Create anonymous filehandle
    my $FILEHANDLE = IO::Handle->new();

# Creates recipe directories (info & data & script), recipe script filenames and writes sbatch header
    my ( $recipe_file_path, $recipe_info_path ) = setup_script(
        {
            active_parameter_href           => $active_parameter_href,
            core_number                     => $core_number,
            directory_id                    => $sample_id,
            FILEHANDLE                      => $FILEHANDLE,
            job_id_href                     => $job_id_href,
            log                             => $log,
            recipe_directory                => $recipe_name,
            recipe_name                     => $recipe_name,
            process_time                    => $time,
            source_environment_commands_ref => \@source_environment_cmds,
            temp_directory                  => $temp_directory,
        }
    );

    ### SHELL

    ## Copy infiles to temp directory
    gnu_cp(
        {
            FILEHANDLE   => $FILEHANDLE,
            infile_path  => $indir_path . $ASTERISK,
            outfile_path => $temp_directory,
        }
    );
    say {$FILEHANDLE} $NEWLINE;

    ## Star-fusion
    say {$FILEHANDLE} q{## Performing fusion transcript detections using } . $recipe_name;

    ## Create sample file
    my $sample_files_path = catfile( $outdir_path, $sample_id . q{_file.txt} );
    create_star_fusion_sample_file(
        {
            FILEHANDLE              => $FILEHANDLE,
            infile_paths_ref        => \@temp_infile_paths,
            infile_lane_prefix_href => $infile_lane_prefix_href,
            samples_file_path       => $sample_files_path,
            sample_id               => $sample_id,
            sample_info_href        => $sample_info_href,
        }
    );
    say {$FILEHANDLE} $NEWLINE;

    star_fusion(
        {
            cpu                   => $core_number,
            examine_coding_effect => 1,
            FILEHANDLE            => $FILEHANDLE,
            genome_lib_dir_path   => $active_parameter_href->{star_fusion_genome_lib_dir},
            output_directory_path => $temp_directory,
            samples_file_path     => $sample_files_path,
        }
    );
    say {$FILEHANDLE} $NEWLINE;

    gnu_cp(
        {
            FILEHANDLE   => $FILEHANDLE,
            infile_path  => catfile( $temp_directory, $ASTERISK ),
            outfile_path => $outdir_path,
            recursive    => 1,
            force        => 1,
        }
    );

    ## Close FILEHANDLES
    close $FILEHANDLE or $log->logcroak(q{Could not close FILEHANDLE});

    if ( $recipe_mode == 1 ) {
        ## Collect QC metadata info for later use
        set_recipe_outfile_in_sample_info(
            {
                path             => $file_paths[0],
                recipe_name      => $recipe_name,
                sample_id        => $sample_id,
                sample_info_href => $sample_info_href,
            }
        );

        submit_recipe(
            {
                dependency_method       => q{sample_to_sample},
                case_id                 => $case_id,
                infile_lane_prefix_href => $infile_lane_prefix_href,
                job_id_href             => $job_id_href,
                log                     => $log,
                job_id_chain            => $recipe_attribute{chain},
                recipe_file_path        => $recipe_file_path,
                sample_id               => $sample_id,
                submission_profile      => $active_parameter_href->{submission_profile},
            }
        );
    }
    return;
}

1;
