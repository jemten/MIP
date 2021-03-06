package MIP::Check::Pipeline;

use 5.026;
use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
use File::Spec::Functions qw{ catfile };
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
    our @EXPORT_OK = qw{ check_rd_dna check_rd_rna check_rd_dna_vcf_rerun };
}

## Constants
Readonly my $SPACE => q{ };

sub check_rd_dna {

## Function : Rare disease DNA pipeline specific checks and parsing
## Arguments: $active_parameter_href           => Active parameters for this analysis hash {REF}
##          : $broadcasts_ref                  => Holds the parameters info for broadcasting later {REF}
##          : $file_info_href                  => File info hash {REF}
##          : $infile_both_strands_prefix_href => The infile(s) without the ".ending" and strand info {REF}
##          : $infile_lane_prefix_href         => Infile(s) without the ".ending" {REF}
##          : $log                             => Log object to write to
##          : $order_parameters_ref            => Order of parameters (for structured output) {REF}
##          : $parameter_href                  => Parameter hash {REF}
##          : $sample_info_href                => Info on samples and case hash {REF}

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $active_parameter_href;
    my $broadcasts_ref;
    my $file_info_href;
    my $infile_both_strands_prefix_href;
    my $infile_lane_prefix_href;
    my $log;
    my $order_parameters_ref;
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
        broadcasts_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$broadcasts_ref,
            strict_type => 1,
        },
        file_info_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$file_info_href,
            strict_type => 1,
        },
        infile_both_strands_prefix_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$infile_both_strands_prefix_href,
            strict_type => 1,
        },
        infile_lane_prefix_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$infile_lane_prefix_href,
            strict_type => 1,
        },
        log => {
            defined  => 1,
            required => 1,
            store    => \$log,
        },
        order_parameters_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$order_parameters_ref,
            strict_type => 1,
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

    use MIP::Check::Parameter qw{ check_mutually_exclusive_parameters
      check_sample_id_in_hash_parameter
      check_sample_id_in_hash_parameter_path
      check_snpsift_keys
      check_vep_custom_annotation
      check_vep_directories };
    use MIP::Check::Path qw{ check_gatk_sample_map_paths check_target_bed_file_suffix };
    use MIP::Check::Reference qw{ check_parameter_metafiles };
    use MIP::File::Format::Config qw{ write_mip_config };
    use MIP::Get::File qw{ get_select_file_contigs };
    use MIP::Parse::Parameter
      qw{ parse_infiles parse_nist_parameters parse_prioritize_variant_callers parse_toml_config_parameters };
    use MIP::Parse::File qw{ parse_fastq_infiles };
    use MIP::Update::Contigs qw{ size_sort_select_file_contigs update_contigs_for_run };
    use MIP::Update::Parameters
      qw{  update_exome_target_bed update_vcfparser_outfile_counter };
    use MIP::Update::Recipes
      qw{ update_prioritize_flag update_recipe_mode_for_analysis_type };
    use MIP::Set::Parameter qw{ set_parameter_to_broadcast };
    use MIP::QC::Sample_info qw{ set_in_sample_info };

    ## Check mutually exclusive parameters and croak if mutually enabled
    check_mutually_exclusive_parameters(
        {
            active_parameter_href => $active_parameter_href,
            log                   => $log,
        }
    );

    ## Update exome_target_bed files with human_genome_reference_source and human_genome_reference_version
    update_exome_target_bed(
        {
            exome_target_bed_file_href => $active_parameter_href->{exome_target_bed},
            human_genome_reference_source =>
              $file_info_href->{human_genome_reference_source},
            human_genome_reference_version =>
              $file_info_href->{human_genome_reference_version},
        }
    );

    ## Checks parameter metafile exists and set build_file parameter
    check_parameter_metafiles(
        {
            parameter_href        => $parameter_href,
            active_parameter_href => $active_parameter_href,
            file_info_href        => $file_info_href,
        }
    );

    ## Check that supplied target file ends with ".bed" and otherwise croaks
  TARGET_FILE:
    foreach my $target_bed_file ( keys %{ $active_parameter_href->{exome_target_bed} } ) {

        check_target_bed_file_suffix(
            {
                log            => $log,
                parameter_name => q{exome_target_bed},
                path           => $target_bed_file,
            }
        );
    }

    ## Update the expected number of outfiles after vcfparser
    update_vcfparser_outfile_counter(
        { active_parameter_href => $active_parameter_href, } );

## Collect select file contigs to loop over downstream
    if ( $active_parameter_href->{vcfparser_select_file} ) {

## Collects sequences contigs used in select file
        @{ $file_info_href->{select_file_contigs} } = get_select_file_contigs(
            {
                select_file_path =>
                  catfile( $active_parameter_href->{vcfparser_select_file} ),
                log => $log,
            }
        );
    }

    ## Check that VEP directory and VEP cache match
    check_vep_directories(
        {
            log                 => $log,
            vep_directory_cache => $active_parameter_href->{vep_directory_cache},
            vep_directory_path  => $active_parameter_href->{vep_directory_path},
        }
    );

    ## Check VEP custom annotations options
    check_vep_custom_annotation(
        {
            log                 => $log,
            vep_custom_ann_href => \%{ $active_parameter_href->{vep_custom_annotation} },
        }
    );

    ## Check sample_id provided in hash parameter is included in the analysis
    check_sample_id_in_hash_parameter(
        {
            active_parameter_href => $active_parameter_href,
            log                   => $log,
            parameter_names_ref   => [qw{ analysis_type expected_coverage }],
            parameter_href        => $parameter_href,
            sample_ids_ref        => \@{ $active_parameter_href->{sample_ids} },
        }
    );

    ## Check sample_id provided in hash path parameter is included in the analysis and only represented once
    check_sample_id_in_hash_parameter_path(
        {
            active_parameter_href => $active_parameter_href,
            log                   => $log,
            parameter_names_ref   => [qw{ exome_target_bed infile_dirs }],
            sample_ids_ref        => \@{ $active_parameter_href->{sample_ids} },
        }
    );

    ## Check that the supplied gatk sample map file paths exists
    check_gatk_sample_map_paths(
        {
            log             => $log,
            sample_map_path => $active_parameter_href->{gatk_genotypegvcfs_ref_gvcf},
        }
    );

    ## Parse parameters with TOML config files
    parse_toml_config_parameters(
        {
            active_parameter_href => $active_parameter_href,
            log                   => $log,
        }
    );

    check_snpsift_keys(
        {
            log => $log,
            snpsift_annotation_files_href =>
              \%{ $active_parameter_href->{snpsift_annotation_files} },
            snpsift_annotation_outinfo_key_href =>
              \%{ $active_parameter_href->{snpsift_annotation_outinfo_key} },
        }
    );

    parse_nist_parameters(
        {
            active_parameter_href => $active_parameter_href,
            log                   => $log,
        }
    );

    if ( $active_parameter_href->{verbose} ) {

        set_parameter_to_broadcast(
            {
                active_parameter_href => $active_parameter_href,
                broadcasts_ref        => $broadcasts_ref,
                order_parameters_ref  => $order_parameters_ref,
                parameter_href        => $parameter_href,
            }
        );
    }

    ## Broadcast set parameters info
    foreach my $parameter_info ( @{$broadcasts_ref} ) {

        $log->info($parameter_info);
    }

    ## Check that all active variant callers have a prioritization order and that the prioritization elements match a supported variant caller
    parse_prioritize_variant_callers(
        {
            active_parameter_href => $active_parameter_href,
            log                   => $log,
            parameter_href        => $parameter_href,
        }
    );

    ## Update prioritize flag depending on analysis run value as some recipes are not applicable for e.g. wes
    $active_parameter_href->{sv_svdb_merge_prioritize} = update_prioritize_flag(
        {
            consensus_analysis_type => $parameter_href->{cache}{consensus_analysis_type},
            prioritize_key          => $active_parameter_href->{sv_svdb_merge_prioritize},
            recipes_ref => [qw{ cnvnator_ar delly_call delly_reformat tiddit }],
        }
    );

    ## Update recipe mode depending on analysis run value as some recipes are not applicable for e.g. wes
    update_recipe_mode_for_analysis_type(
        {
            active_parameter_href   => $active_parameter_href,
            consensus_analysis_type => $parameter_href->{cache}{consensus_analysis_type},
            log                     => $log,
            recipes_ref             => [
                qw{ cnvnator_ar delly_call delly_reformat expansionhunter tiddit samtools_subsample_mt }
            ],
        }
    );

    ## Write config file for case
    write_mip_config(
        {
            active_parameter_href => $active_parameter_href,
            log                   => $log,
            remove_keys_ref       => [qw{ associated_recipe }],
            sample_info_href      => $sample_info_href,
        }
    );

    ## Update contigs depending on settings in run (wes or if only male samples)
    update_contigs_for_run(
        {
            analysis_type_href  => \%{ $active_parameter_href->{analysis_type} },
            exclude_contigs_ref => \@{ $active_parameter_href->{exclude_contigs} },
            file_info_href      => $file_info_href,
            found_male          => $active_parameter_href->{found_male},
            log                 => $log,
        }
    );

    ## Sorts array depending on reference array. NOTE: Only entries present in reference array will survive in sorted array.
    @{ $file_info_href->{sorted_select_file_contigs} } = size_sort_select_file_contigs(
        {
            consensus_analysis_type => $parameter_href->{cache}{consensus_analysis_type},
            file_info_href          => $file_info_href,
            hash_key_sort_reference => q{contigs_size_ordered},
            hash_key_to_sort        => q{select_file_contigs},
            log                     => $log,
        }
    );

    ## Get the ".fastq(.gz)" files from the supplied infiles directory. Checks if the files exist
    parse_infiles(
        {
            active_parameter_href => $active_parameter_href,
            file_info_href        => $file_info_href,
            log                   => $log,
        }
    );

    ## Reformat file names to MIP format, get file name info and add info to sample_info
    parse_fastq_infiles(
        {
            active_parameter_href           => $active_parameter_href,
            file_info_href                  => $file_info_href,
            infile_both_strands_prefix_href => $infile_both_strands_prefix_href,
            infile_lane_prefix_href         => $infile_lane_prefix_href,
            log                             => $log,
            sample_info_href                => $sample_info_href,
        }
    );

    ## Add to sample info
    set_in_sample_info(
        {
            active_parameter_href => $active_parameter_href,
            file_info_href        => $file_info_href,
            sample_info_href      => $sample_info_href,
        }
    );

    return;
}

sub check_rd_rna {

## Function : Rare disease RNA pipeline specific checks and parsing
## Arguments: $active_parameter_href           => Active parameters for this analysis hash {REF}
##          : $broadcasts_ref                  => Holds the parameters info for broadcasting later {REF}
##          : $file_info_href                  => File info hash {REF}
##          : $infile_both_strands_prefix_href => The infile(s) without the ".ending" and strand info {REF}
##          : $infile_lane_prefix_href         => Infile(s) without the ".ending" {REF}
##          : $log                             => Log object to write to
##          : $order_parameters_ref            => Order of parameters (for structured output) {REF}
##          : $parameter_href                  => Parameter hash {REF}
##          : $sample_info_href                => Info on samples and case hash {REF}

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $active_parameter_href;
    my $broadcasts_ref;
    my $file_info_href;
    my $infile_both_strands_prefix_href;
    my $infile_lane_prefix_href;
    my $log;
    my $order_parameters_ref;
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
        broadcasts_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$broadcasts_ref,
            strict_type => 1,
        },
        file_info_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$file_info_href,
            strict_type => 1,
        },
        infile_both_strands_prefix_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$infile_both_strands_prefix_href,
            strict_type => 1,
        },
        infile_lane_prefix_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$infile_lane_prefix_href,
            strict_type => 1,
        },
        log => {
            defined  => 1,
            required => 1,
            store    => \$log,
        },
        order_parameters_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$order_parameters_ref,
            strict_type => 1,
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

    use MIP::Check::Parameter
      qw{ check_salmon_compatibility check_sample_id_in_hash_parameter check_sample_id_in_hash_parameter_path check_sample_id_in_parameter_value };
    use MIP::Check::Reference qw{ check_parameter_metafiles };
    use MIP::File::Format::Config qw{ write_mip_config };
    use MIP::Parse::Parameter qw{ parse_infiles };
    use MIP::Parse::File qw{ parse_fastq_infiles };
    use MIP::Set::Parameter qw{ set_parameter_to_broadcast };
    use MIP::Update::Contigs qw{ update_contigs_for_run };
    use MIP::QC::Sample_info qw{ set_in_sample_info };

    ## Checks parameter metafile exists and set build_file parameter
    check_parameter_metafiles(
        {
            parameter_href        => $parameter_href,
            active_parameter_href => $active_parameter_href,
            file_info_href        => $file_info_href,
        }
    );

    ## Check sample_id provided in hash parameter is included in the analysis
    check_sample_id_in_hash_parameter(
        {
            active_parameter_href => $active_parameter_href,
            log                   => $log,
            parameter_names_ref   => [qw{ analysis_type }],
            parameter_href        => $parameter_href,
            sample_ids_ref        => \@{ $active_parameter_href->{sample_ids} },
        }
    );

    ## Check sample_id provided in hash path parameter is included in the analysis and only represented once
    check_sample_id_in_hash_parameter_path(
        {
            active_parameter_href => $active_parameter_href,
            log                   => $log,
            parameter_names_ref   => [qw{ infile_dirs }],
            sample_ids_ref        => \@{ $active_parameter_href->{sample_ids} },
        }
    );

    ## Check sample_id provided in hash parameter is included in the analysis
    check_sample_id_in_parameter_value(
        {
            active_parameter_href => $active_parameter_href,
            log                   => $log,
            parameter_names_ref   => [qw{ is_from_sample }],
            parameter_href        => $parameter_href,
            sample_ids_ref        => \@{ $active_parameter_href->{sample_ids} },
        }
    );

    if ( $active_parameter_href->{verbose} ) {

        set_parameter_to_broadcast(
            {
                active_parameter_href => $active_parameter_href,
                broadcasts_ref        => $broadcasts_ref,
                order_parameters_ref  => $order_parameters_ref,
                parameter_href        => $parameter_href,
            }
        );
    }

    ## Broadcast set parameters info
    foreach my $parameter_info ( @{$broadcasts_ref} ) {

        $log->info($parameter_info);
    }

    ## Write config file for case
    write_mip_config(
        {
            active_parameter_href => $active_parameter_href,
            log                   => $log,
            remove_keys_ref       => [qw{ associated_recipe }],
            sample_info_href      => $sample_info_href,
        }
    );

    ## Update contigs depending on settings in run (wes or if only male samples)
    update_contigs_for_run(
        {
            analysis_type_href  => \%{ $active_parameter_href->{analysis_type} },
            exclude_contigs_ref => \@{ $active_parameter_href->{exclude_contigs} },
            file_info_href      => $file_info_href,
            found_male          => $active_parameter_href->{found_male},
            log                 => $log,
        }
    );

    ## Get the ".fastq(.gz)" files from the supplied infiles directory. Checks if the files exist
    parse_infiles(
        {
            active_parameter_href => $active_parameter_href,
            file_info_href        => $file_info_href,
            log                   => $log,
        }
    );

    ## Reformat file names to MIP format, get file name info and add info to sample_info
    parse_fastq_infiles(
        {
            active_parameter_href           => $active_parameter_href,
            file_info_href                  => $file_info_href,
            infile_both_strands_prefix_href => $infile_both_strands_prefix_href,
            infile_lane_prefix_href         => $infile_lane_prefix_href,
            log                             => $log,
            sample_info_href                => $sample_info_href,
        }
    );

    ## Add to sample info
    set_in_sample_info(
        {
            active_parameter_href => $active_parameter_href,
            file_info_href        => $file_info_href,
            sample_info_href      => $sample_info_href,
        }
    );

    ## Check salmon compability
    check_salmon_compatibility(
        {
            active_parameter_href   => $active_parameter_href,
            infile_lane_prefix_href => $infile_lane_prefix_href,
            log                     => $log,
            parameter_href          => $parameter_href,
            sample_info_href        => $sample_info_href,
        }
    );

    return;
}

sub check_rd_dna_vcf_rerun {

## Function : Rare disease DNA vcf rerun pipeline specific checks and parsing
## Arguments: $active_parameter_href           => Active parameters for this analysis hash {REF}
##          : $broadcasts_ref                  => Holds the parameters info for broadcasting later {REF}
##          : $file_info_href                  => File info hash {REF}
##          : $infile_lane_prefix_href         => Infile(s) without the ".ending" {REF}
##          : $log                             => Log object to write to
##          : $order_parameters_ref            => Order of parameters (for structured output) {REF}
##          : $parameter_href                  => Parameter hash {REF}
##          : $sample_info_href                => Info on samples and case hash {REF}

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $active_parameter_href;
    my $broadcasts_ref;
    my $file_info_href;
    my $infile_lane_prefix_href;
    my $log;
    my $order_parameters_ref;
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
        broadcasts_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$broadcasts_ref,
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
        log => {
            defined  => 1,
            required => 1,
            store    => \$log,
        },
        order_parameters_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$order_parameters_ref,
            strict_type => 1,
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

    use MIP::Check::Parameter
      qw{ check_sample_id_in_hash_parameter check_snpsift_keys check_vep_directories };
    use MIP::Check::Reference qw{ check_parameter_metafiles };
    use MIP::File::Format::Config qw{ write_mip_config };
    use MIP::Get::File qw{ get_select_file_contigs };
    use MIP::Update::Contigs qw{ size_sort_select_file_contigs update_contigs_for_run };
    use MIP::Update::Parameters qw{ update_vcfparser_outfile_counter };
    use MIP::Set::Parameter qw{ set_parameter_to_broadcast };
    use MIP::QC::Sample_info qw{ set_in_sample_info };

    ## Check sample_id provided in hash parameter is included in the analysis
    check_sample_id_in_hash_parameter(
        {
            active_parameter_href => $active_parameter_href,
            log                   => $log,
            parameter_names_ref   => [qw{ analysis_type }],
            parameter_href        => $parameter_href,
            sample_ids_ref        => \@{ $active_parameter_href->{sample_ids} },
        }
    );

    ## Checks parameter metafile exists and set build_file parameter
    check_parameter_metafiles(
        {
            parameter_href        => $parameter_href,
            active_parameter_href => $active_parameter_href,
            file_info_href        => $file_info_href,
        }
    );

    ## Update the expected number of outfiles after vcfparser
    update_vcfparser_outfile_counter(
        { active_parameter_href => $active_parameter_href, } );

## Collect select file contigs to loop over downstream
    if ( $active_parameter_href->{vcfparser_select_file} ) {

## Collects sequences contigs used in select file
        @{ $file_info_href->{select_file_contigs} } = get_select_file_contigs(
            {
                select_file_path =>
                  catfile( $active_parameter_href->{vcfparser_select_file} ),
                log => $log,
            }
        );
    }

    ## Check that VEP directory and VEP cache match
    check_vep_directories(
        {
            log                 => $log,
            vep_directory_cache => $active_parameter_href->{vep_directory_cache},
            vep_directory_path  => $active_parameter_href->{vep_directory_path},
        }
    );

    ## Check VEP custom annotations options
    check_vep_custom_annotation(
        {
            log                 => $log,
            vep_custom_ann_href => \%{ $active_parameter_href->{vep_custom_annotation} },
        }
    );

    check_snpsift_keys(
        {
            log => $log,
            snpsift_annotation_files_href =>
              \%{ $active_parameter_href->{snpsift_annotation_files} },
            snpsift_annotation_outinfo_key_href =>
              \%{ $active_parameter_href->{snpsift_annotation_outinfo_key} },
        }
    );

    if ( $active_parameter_href->{verbose} ) {

        set_parameter_to_broadcast(
            {
                active_parameter_href => $active_parameter_href,
                broadcasts_ref        => $broadcasts_ref,
                order_parameters_ref  => $order_parameters_ref,
                parameter_href        => $parameter_href,
            }
        );
    }

    ## Broadcast set parameters info
    foreach my $parameter_info ( @{$broadcasts_ref} ) {

        $log->info($parameter_info);
    }

    ## Write config file for case
    write_mip_config(
        {
            active_parameter_href => $active_parameter_href,
            log                   => $log,
            remove_keys_ref       => [qw{ associated_recipe }],
            sample_info_href      => $sample_info_href,
        }
    );

    ## Update contigs depending on settings in run (wes or if only male samples)
    update_contigs_for_run(
        {
            analysis_type_href  => \%{ $active_parameter_href->{analysis_type} },
            exclude_contigs_ref => \@{ $active_parameter_href->{exclude_contigs} },
            file_info_href      => $file_info_href,
            found_male          => $active_parameter_href->{found_male},
            log                 => $log,
        }
    );

    ## Sorts array depending on reference array. NOTE: Only entries present in reference array will survive in sorted array.
    @{ $file_info_href->{sorted_select_file_contigs} } = size_sort_select_file_contigs(
        {
            consensus_analysis_type => $parameter_href->{cache}{consensus_analysis_type},
            file_info_href          => $file_info_href,
            hash_key_sort_reference => q{contigs_size_ordered},
            hash_key_to_sort        => q{select_file_contigs},
            log                     => $log,
        }
    );

    ## Add to sample info
    set_in_sample_info(
        {
            active_parameter_href => $active_parameter_href,
            file_info_href        => $file_info_href,
            sample_info_href      => $sample_info_href,
        }
    );

    return;
}

1;
