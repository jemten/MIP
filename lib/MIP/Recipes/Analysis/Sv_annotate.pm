package MIP::Recipes::Analysis::Sv_annotate;

use 5.026;
use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
use File::Basename qw{ dirname };
use File::Spec::Functions qw{ catdir catfile devnull splitpath };
use open qw{ :encoding(UTF-8) :std };
use Params::Check qw{ allow check last_error };
use strict;
use utf8;
use warnings;
use warnings qw{ FATAL utf8 };

## CPANM
use autodie qw{ :all };
use List::MoreUtils qw { any };
use Readonly;

BEGIN {

    require Exporter;
    use base qw{ Exporter };

    # Set the version for version checking
    our $VERSION = 1.05;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw{ analysis_sv_annotate };

}

## Constants
Readonly my $ASTERISK     => q{*};
Readonly my $COLON        => q{:};
Readonly my $DASH         => q{-};
Readonly my $DOT          => q{.};
Readonly my $DOUBLE_QUOTE => q{"};
Readonly my $EMPTY_STR    => q{};
Readonly my $NEWLINE      => qq{\n};
Readonly my $PIPE         => q{|};
Readonly my $SPACE        => q{ };
Readonly my $UNDERSCORE   => q{_};

sub analysis_sv_annotate {

## Function : Annotate structural variants
## Returns  :
## Arguments: $active_parameter_href   => Active parameters for this analysis hash {REF}
##          : $case_id                 => Family id
##          : $file_info_href          => File info hash {REF}
##          : $infile_lane_prefix_href => Infile(s) without the ".ending" {REF}
##          : $job_id_href             => Job id hash {REF}
##          : $parameter_href          => Parameter hash {REF}
##          : $recipe_name             => Program name
##          : $reference_dir           => MIP reference directory
##          : $sample_info_href        => Info on samples and case hash {REF}
##          : $temp_directory          => Temporary directory {REF}

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
        reference_dir => {
            default     => $arg_href->{active_parameter_href}{reference_dir},
            store       => \$reference_dir,
            strict_type => 1,
        },
        temp_directory => {
            default     => $arg_href->{active_parameter_href}{temp_directory},
            store       => \$temp_directory,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    use MIP::Get::File qw{ get_io_files };
    use MIP::Get::Parameter
      qw{ get_package_source_env_cmds get_recipe_attributes get_recipe_parameters };
    use MIP::Gnu::Coreutils qw(gnu_mv);
    use MIP::IO::Files qw{ migrate_file };
    use MIP::Parse::File qw{ parse_io_outfiles };
    use MIP::Processmanagement::Processes qw{ submit_recipe };
    use MIP::Program::Variantcalling::Bcftools
      qw{ bcftools_annotate bcftools_filter bcftools_view bcftools_view_and_index_vcf };
    use MIP::Program::Variantcalling::Genmod qw{ genmod_annotate };
    use MIP::Program::Variantcalling::Picardtools qw{ sort_vcf };
    use MIP::Program::Variantcalling::Svdb qw{ svdb_query };
    use MIP::Program::Variantcalling::Vcfanno qw{ vcfanno };
    use MIP::QC::Sample_info qw{ set_recipe_outfile_in_sample_info };
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
            temp_directory => $temp_directory,
        }
    );
    my $infile_name_prefix = $io{in}{file_name_prefix};
    my $infile_path_prefix = $io{in}{file_path_prefix};
    my $infile_suffix      = $io{in}{file_suffix};
    my $infile_path = $infile_path_prefix . substr( $infile_suffix, 0, 2 ) . $ASTERISK;
    my $temp_infile_path_prefix = $io{temp}{file_path_prefix};
    my $temp_infile_path        = $temp_infile_path_prefix . $infile_suffix;

    my $consensus_analysis_type = $parameter_href->{cache}{consensus_analysis_type};
    my $job_id_chain            = get_recipe_attributes(
        {
            parameter_href => $parameter_href,
            recipe_name    => $recipe_name,
            attribute      => q{chain},
        }
    );
    my $recipe_mode        = $active_parameter_href->{$recipe_name};
    my $sequence_dict_file = catfile( $reference_dir,
        $file_info_href->{human_genome_reference_name_prefix} . $DOT . q{dict} );
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
                chain_id               => $job_id_chain,
                id                     => $case_id,
                file_info_href         => $file_info_href,
                file_name_prefixes_ref => [$infile_name_prefix],
                outdata_dir            => $active_parameter_href->{outdata_dir},
                parameter_href         => $parameter_href,
                recipe_name            => $recipe_name,
                temp_directory         => $temp_directory,
            }
        )
    );

    my $outdir_path_prefix       = $io{out}{dir_path_prefix};
    my $outfile_name_prefix      = $io{out}{file_name_prefix};
    my $outfile_path_prefix      = $io{out}{file_path_prefix};
    my $outfile_suffix           = $io{out}{file_suffix};
    my $outfile_path             = $outfile_path_prefix . $outfile_suffix;
    my $temp_outfile_path_prefix = $io{temp}{file_path_prefix};
    my $temp_outfile_suffix      = $io{temp}{file_suffix};
    my $temp_outfile_path        = $temp_outfile_path_prefix . $temp_outfile_suffix;

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
            temp_directory                  => $temp_directory,
        }
    );

    ## Split to enable submission to &sample_info_qc later
    my ( $volume, $directory, $stderr_file ) =
      splitpath( $recipe_info_path . $DOT . q{stderr.txt} );
    my $stderrfile_path = $recipe_info_path . $DOT . q{stderr.txt};

    ### SHELL:

    ## Copy file(s) to temporary directory
    say {$FILEHANDLE} q{## Copy file(s) to temporary directory};
    migrate_file(
        {
            FILEHANDLE   => $FILEHANDLE,
            infile_path  => $infile_path,
            outfile_path => $temp_directory
        }
    );
    say {$FILEHANDLE} q{wait}, $NEWLINE;

    ## Alternative file tag
    my $alt_file_tag = $EMPTY_STR;

    if ( $active_parameter_href->{sv_svdb_query} ) {

        ## Set for first infile
        my $svdb_infile_path = $temp_infile_path;

        ## Update alternative ending
        $alt_file_tag .= $UNDERSCORE . q{svdbq};

        ## Ensure correct infile
        my $annotation_file_counter = 0;

        ## Ensure correct outfiles
        my $outfile_tracker = 0;

      QUERIES:
        while ( my ( $query_db_file, $query_db_tag ) =
            each %{ $active_parameter_href->{sv_svdb_query_db_files} } )
        {

            if ($annotation_file_counter) {

                $svdb_infile_path =
                    $temp_infile_path_prefix
                  . $alt_file_tag
                  . $infile_suffix
                  . $DOT
                  . $outfile_tracker;

                ## Increment now that infile has been set
                $outfile_tracker++;
            }
            svdb_query(
                {
                    bnd_distance    => 25_000,
                    dbfile_path     => $query_db_file,
                    FILEHANDLE      => $FILEHANDLE,
                    frequency_tag   => $query_db_tag . q{AF},
                    hit_tag         => $query_db_tag,
                    infile_path     => $svdb_infile_path,
                    stdoutfile_path => $temp_infile_path_prefix
                      . $alt_file_tag
                      . $infile_suffix
                      . $DOT
                      . $outfile_tracker,
                    overlap => 0.8,
                }
            );
            say {$FILEHANDLE} $NEWLINE;
            $annotation_file_counter++;
        }

        ## Rename to remove outfile_tracker
        gnu_mv(
            {
                FILEHANDLE  => $FILEHANDLE,
                infile_path => $temp_infile_path_prefix
                  . $alt_file_tag
                  . $infile_suffix
                  . $DOT
                  . $outfile_tracker,
                outfile_path => $temp_infile_path_prefix . $alt_file_tag . $infile_suffix,
            }
        );
        say {$FILEHANDLE} $NEWLINE;
    }

    ## Alternative file tag
    my $outfile_alt_file_tag = $alt_file_tag . $UNDERSCORE . q{sorted};

    ## Writes sbatch code to supplied filehandle to sort variants in vcf format
    sort_vcf(
        {
            active_parameter_href => $active_parameter_href,
            FILEHANDLE            => $FILEHANDLE,
            infile_paths_ref =>
              [ $temp_infile_path_prefix . $alt_file_tag . $infile_suffix ],
            outfile => $temp_outfile_path_prefix
              . $outfile_alt_file_tag
              . $outfile_suffix,
            sequence_dict_file => $sequence_dict_file,
        }
    );
    say {$FILEHANDLE} $NEWLINE;

    $alt_file_tag = $outfile_alt_file_tag;

    ## Remove FILTER ne PASS
    if ( $active_parameter_href->{sv_bcftools_view_filter} ) {

        say {$FILEHANDLE} q{## Remove FILTER ne PASS};
        bcftools_view(
            {
                apply_filters_ref => [qw{ PASS }],
                FILEHANDLE        => $FILEHANDLE,
                infile_path       => $temp_outfile_path_prefix
                  . $alt_file_tag
                  . $outfile_suffix,
                outfile_path => $temp_outfile_path_prefix
                  . $alt_file_tag
                  . $UNDERSCORE . q{filt}
                  . $outfile_suffix,
            }
        );
        say {$FILEHANDLE} $NEWLINE;

        ## Update file tag
        $alt_file_tag .= $UNDERSCORE . q{filt};
    }

    ## Remove common variants
    if ( $active_parameter_href->{sv_frequency_filter} ) {

        say {$FILEHANDLE} q{## Remove common variants};
        vcfanno(
            {
                FILEHANDLE  => $FILEHANDLE,
                infile_path => $temp_outfile_path_prefix
                  . $alt_file_tag
                  . $outfile_suffix,
                stderrfile_path_append => $stderrfile_path,
                toml_configfile_path   => $active_parameter_href->{fqf_vcfanno_config},
            }
        );
        print {$FILEHANDLE} $PIPE . $SPACE;

        ## Update file tag
        $alt_file_tag .= $UNDERSCORE . q{bcftools_filter};

        ## Build the exclude filter command
        my $exclude_filter = _build_bcftools_filter(
            {
                vcfanno_file_toml => $active_parameter_href->{fqf_vcfanno_config},
                fqf_bcftools_filter_threshold =>
                  $active_parameter_href->{fqf_bcftools_filter_threshold},
            }
        );

        bcftools_filter(
            {
                FILEHANDLE   => $FILEHANDLE,
                infile_path  => $DASH,
                outfile_path => $temp_outfile_path_prefix
                  . $alt_file_tag
                  . $outfile_suffix,
                output_type            => q{v},
                stderrfile_path_append => $stderrfile_path,
                exclude                => $exclude_filter,
            }
        );
        say {$FILEHANDLE} $NEWLINE;
    }

    ## Annotate 1000G structural variants
    if ( $active_parameter_href->{sv_vcfanno} ) {

        say {$FILEHANDLE} q{## Annotate 1000G structural variants};
        vcfanno(
            {
                ends        => 1,
                FILEHANDLE  => $FILEHANDLE,
                infile_path => $temp_outfile_path_prefix
                  . $alt_file_tag
                  . $outfile_suffix,
                luafile_path         => $active_parameter_href->{sv_vcfanno_lua},
                toml_configfile_path => $active_parameter_href->{sv_vcfanno_config},
            }
        );
        print {$FILEHANDLE} $PIPE . $SPACE;

        ## Remove "[" and "]" from INFO as it breaks vcf format
        print {$FILEHANDLE}
q?perl -nae 'if($_=~/^#/) {print $_} else {$F[7]=~s/\[||\]//g; print join("\t", @F), "\n"}' ?;

        ## Update file tag
        $alt_file_tag .= $UNDERSCORE . q{vcfanno};

        say {$FILEHANDLE} q{>}
          . $SPACE
          . $temp_outfile_path_prefix
          . $alt_file_tag
          . $outfile_suffix, $NEWLINE;

        if ( $recipe_mode == 1 ) {

            set_recipe_outfile_in_sample_info(
                {
                    path             => catfile( $directory, $stderr_file ),
                    recipe_name      => q{sv_annotate},
                    sample_info_href => $sample_info_href,
                }
            );
        }

        say {$FILEHANDLE} q{## Add header for 1000G annotation of structural variants};
        bcftools_annotate(
            {
                FILEHANDLE => $FILEHANDLE,
                headerfile_path =>
                  $active_parameter_href->{sv_vcfannotation_header_lines_file},
                infile_path => $temp_outfile_path_prefix
                  . $alt_file_tag
                  . $outfile_suffix,
                outfile_path => $temp_outfile_path_prefix
                  . $alt_file_tag
                  . $UNDERSCORE
                  . q{bcftools_annotate}
                  . $outfile_suffix,
                output_type => q{v},
            }
        );
        say {$FILEHANDLE} $NEWLINE;

        ## Update file tag
        $alt_file_tag .= $UNDERSCORE . q{bcftools_annotate};
    }

    ## Then we have something to rename
    if ( $alt_file_tag ne $EMPTY_STR ) {

        ## Writes sbatch code to supplied filehandle to sort variants in vcf format
        sort_vcf(
            {
                active_parameter_href => $active_parameter_href,
                FILEHANDLE            => $FILEHANDLE,
                infile_paths_ref =>
                  [ $temp_outfile_path_prefix . $alt_file_tag . $outfile_suffix ],
                outfile            => $temp_outfile_path,
                sequence_dict_file => $sequence_dict_file,
            }
        );
        say {$FILEHANDLE} $NEWLINE;
    }

    ## Copies file from temporary directory.
    say {$FILEHANDLE} q{## Copy file from temporary directory};
    migrate_file(
        {
            FILEHANDLE   => $FILEHANDLE,
            infile_path  => $temp_outfile_path,
            outfile_path => $outdir_path_prefix,
        }
    );
    say {$FILEHANDLE} q{wait}, $NEWLINE;

    close $FILEHANDLE or $log->logcroak(q{Could not close FILEHANDLE});

    if ( $recipe_mode == 1 ) {

        set_recipe_outfile_in_sample_info(
            {
                path             => $outfile_path,
                recipe_name      => q{sv_annotate},
                sample_info_href => $sample_info_href,
            }
        );

        submit_recipe(
            {
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
    return;
}

sub _build_bcftools_filter {

## Function : Build the exclude filter command
## Returns  :
## Arguments: $fqf_bcftools_filter_threshold => Exclude variants with frequency above filter threshold
##          : $vcfanno_file_toml             => Toml config file

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $fqf_bcftools_filter_threshold;
    my $vcfanno_file_toml;

    my $tmpl = {
        fqf_bcftools_filter_threshold => {
            defined     => 1,
            required    => 1,
            store       => \$fqf_bcftools_filter_threshold,
            strict_type => 1,
        },
        vcfanno_file_toml => {
            defined     => 1,
            required    => 1,
            store       => \$vcfanno_file_toml,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    use MIP::File::Format::Toml qw{ load_toml };

    my %vcfanno_config = load_toml( { toml_file_path => $vcfanno_file_toml, } );

    my $exclude_filter;
    my $threshold = $SPACE . q{>} . $SPACE . $fqf_bcftools_filter_threshold . $SPACE;

  ANNOTATION:
    foreach my $annotation_href ( @{ $vcfanno_config{annotation} } ) {

        $exclude_filter =
            $DOUBLE_QUOTE
          . q{INFO/}
          . join( $threshold . $PIPE . $SPACE . q{INFO/}, @{ $annotation_href->{names} } )
          . $threshold
          . $DOUBLE_QUOTE;
    }
    return $exclude_filter;
}

1;
