package MIP::Recipes::Analysis::Gffcompare;

use 5.026;
use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
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
    our $VERSION = 1.03;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw{ analysis_gffcompare };

}

## Constants
Readonly my $ASTERISK   => q{*};
Readonly my $DOT        => q{.};
Readonly my $NEWLINE    => qq{\n};
Readonly my $UNDERSCORE => q{_};

sub analysis_gffcompare {

## Function : Compare assembled gtf files to a refrence using GffCompare.
## Returns  :
## Arguments: $active_parameter_href   => Active parameters for this analysis hash {REF}
##          : $case_id                 => Family id
##          : $file_info_href          => File info hash {REF}
##          : $infile_lane_prefix_href => Infile(s) without the ".ending" {REF}
##          : $job_id_href             => Job id hash {REF}
##          : $parameter_href          => Parameter hash {REF}
##          : $profile_base_command    => Submission profile base command
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
            allow       => qr{ \A\d+\z }xsm,
            default     => 0,
            store       => \$xargs_file_counter,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    use MIP::Get::File qw{ get_io_files };
    use MIP::Get::Parameter qw{ get_recipe_parameters get_recipe_attributes };
    use MIP::Gnu::Coreutils qw{ gnu_mv };
    use MIP::Parse::File qw{ parse_io_outfiles };
    use MIP::Processmanagement::Processes qw{ submit_recipe };
    use MIP::Program::Variantcalling::Gffcompare qw{ gffcompare };
    use MIP::Script::Setup_script qw{ setup_script };
    use MIP::QC::Sample_info qw{ set_recipe_outfile_in_sample_info };

    ### PREPROCESSING:

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
    my $infile_name_prefix = $io{in}{file_name_prefix};
    my $infile_path_prefix = $io{in}{file_path_prefix};
    my $infile_suffix      = $io{in}{file_suffix};
    my $indir_path         = $io{in}{dir_path};
    my $infile_name        = $infile_name_prefix . $infile_suffix;
    my $infile_path        = $infile_path_prefix . $infile_suffix;

    ## GffCompare can take multiple inputs. Add input gtfs as necessary
    my @infile_paths = ($infile_path);

    my %recipe_attribute = get_recipe_attributes(
        {
            parameter_href => $parameter_href,
            recipe_name    => $recipe_name,
        }
    );
    my $job_id_chain        = $recipe_attribute{chain};
    my $recipe_mode         = $active_parameter_href->{$recipe_name};
    my $annotationfile_path = $active_parameter_href->{transcript_annotation};
    my ( $core_number, $time, @source_environment_cmds ) = get_recipe_parameters(
        {
            active_parameter_href => $active_parameter_href,
            recipe_name           => $recipe_name,
        }
    );

    ## Outpaths
    ## Set and get the io files per chain, id and stream
    %io = (
        %io,
        parse_io_outfiles(
            {
                chain_id               => $job_id_chain,
                file_info_href         => $file_info_href,
                file_name_prefixes_ref => [$infile_name_prefix],
                id                     => $sample_id,
                outdata_dir            => $active_parameter_href->{outdata_dir},
                parameter_href         => $parameter_href,
                recipe_name            => $recipe_name,
                temp_directory         => $temp_directory,
            }
        )
    );
    my $outfile_path        = ${ $io{out}{file_paths} }[0];
    my $outfile_name_prefix = $io{out}{file_name_prefix};
    my $outfile_name        = ${ $io{out}{file_names} }[0];
    my $outfile_path_prefix = $io{out}{file_path_prefix};

    ## Filehandles
    # Create anonymous filehandle
    my $FILEHANDLE = IO::Handle->new();

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

    ## GFFcompare
    say {$FILEHANDLE} q{## GffCompare};
    gffcompare(
        {
            FILEHANDLE           => $FILEHANDLE,
            genome_sequence_path => $active_parameter_href->{human_genome_reference},
            gtf_reference_path   => $active_parameter_href->{transcript_annotation},
            ignore_non_overlapping_ref => 1,
            infile_paths_ref           => \@infile_paths,
            outfile_path_prefix        => $outfile_path_prefix,
        }
    );
    say {$FILEHANDLE} $NEWLINE;

    ## Rename output files
    say {$FILEHANDLE} q{## Rename and move GFFCompare output};
    my $gff_output_path = $outfile_path_prefix . $DOT . q{annotated.gtf};
    if ( scalar @infile_paths > 1 ) {
        $gff_output_path = $outfile_path_prefix . $DOT . q{combined.gtf};
    }
    my $refmap_infile_path = catfile( $indir_path,
        $outfile_name_prefix . $DOT . $infile_name . $DOT . q{refmap} );
    my $tmap_infile_path =
      catfile( $indir_path, $outfile_name_prefix . $DOT . $infile_name . $DOT . q{tmap} );

    my @file_names = (
        [ $gff_output_path,    $outfile_path ],
        [ $refmap_infile_path, $outfile_path_prefix . $DOT . q{refmap} ],
        [ $tmap_infile_path,   $outfile_path_prefix . $DOT . q{tmap} ],
    );

    foreach my $files_ref (@file_names) {
        gnu_mv(
            {
                FILEHANDLE   => $FILEHANDLE,
                infile_path  => $files_ref->[0],
                outfile_path => $files_ref->[1],
            }
        );
        say {$FILEHANDLE} $NEWLINE;
    }

    ## Close FILEHANDLE
    close $FILEHANDLE;

    if ( $recipe_mode == 1 ) {

        ## Collect QC metadata info for later use
        set_recipe_outfile_in_sample_info(
            {
                infile           => $outfile_name,
                path             => $outfile_path,
                recipe_name      => $recipe_name,
                sample_id        => $sample_id,
                sample_info_href => $sample_info_href,
            }
        );

        submit_recipe(
            {
              base_command            => $profile_base_command,
                case_id                 => $case_id,
                dependency_method       => q{sample_to_island},
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

1;
