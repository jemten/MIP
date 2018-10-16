package MIP::Recipes::Pipeline::Rd_dna;

use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
use File::Spec::Functions qw{ catdir catfile };
use open qw{ :encoding(UTF-8) :std };
use Params::Check qw{ check allow last_error };
use strict;
use utf8;
use warnings;
use warnings qw{ FATAL utf8 };

## CPANM
use List::MoreUtils qw { any };
use Readonly;

##MIPs lib/
use MIP::Delete::List qw{ delete_male_contig };

BEGIN {

    require Exporter;
    use base qw{ Exporter };

    # Set the version for version checking
    our $VERSION = 1.07;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw{ pipeline_rd_dna };
}

## Constants
Readonly my $SPACE => q{ };

sub pipeline_rd_dna {

## Function : Pipeline recipe for wes and or wgs data analysis.
## Returns  :
## Arguments: $active_parameter_href           => Active parameters for this analysis hash {REF}
##          : $broadcasts_ref                  => Holds the parameters info for broadcasting later {REF}
##          : $file_info_href                  => File info hash {REF}
##          : $infile_both_strands_prefix_href => The infile(s) without the ".ending" and strand info {REF}
##          : $infile_lane_prefix_href         => Infile(s) without the ".ending" {REF}
##          : $job_id_href                     => Job id hash {REF}
##          : $log                             => Log object to write to
##          : $order_parameters_ref            => Order of parameters (for structured output) {REF}
##          : $order_programs_ref              => Order of programs
##          : $outaligner_dir                  => Outaligner dir used in the analysis
##          : $parameter_href                  => Parameter hash {REF}
##          : $sample_info_href                => Info on samples and family hash {REF}

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $active_parameter_href;
    my $broadcasts_ref;
    my $file_info_href;
    my $infile_both_strands_prefix_href;
    my $infile_lane_prefix_href;
    my $job_id_href;
    my $log;
    my $order_parameters_ref;
    my $order_programs_ref;
    my $parameter_href;
    my $sample_info_href;

    ## Default(s)
    my $outaligner_dir;

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
        order_parameters_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$order_parameters_ref,
            strict_type => 1,
        },
        order_programs_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$order_programs_ref,
            strict_type => 1,
        },
        outaligner_dir => {
            default     => $arg_href->{active_parameter_href}{outaligner_dir},
            store       => \$outaligner_dir,
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

    use MIP::Check::Pipeline qw{ check_rd_dna };

    ## Recipes
    use MIP::Log::MIP_log4perl qw{ log_display_program_for_user };
    use MIP::Recipes::Analysis::Analysisrunstatus
      qw{ analysis_analysisrunstatus };
    use MIP::Recipes::Analysis::Bamcalibrationblock
      qw{ analysis_bamcalibrationblock };
    use MIP::Recipes::Analysis::Bcftools_mpileup
      qw { analysis_bcftools_mpileup };
    use MIP::Recipes::Analysis::Bwa_mem qw{ analysis_bwa_mem };
    use MIP::Recipes::Analysis::Chanjo_sex_check
      qw{ analysis_chanjo_sex_check };
    use MIP::Recipes::Analysis::Cnvnator qw{ analysis_cnvnator };
    use MIP::Recipes::Analysis::Delly_call qw{ analysis_delly_call };
    use MIP::Recipes::Analysis::Delly_reformat qw{ analysis_delly_reformat };
    use MIP::Recipes::Analysis::Endvariantannotationblock
      qw{ analysis_endvariantannotationblock };
    use MIP::Recipes::Analysis::Expansionhunter qw{ analysis_expansionhunter };
    use MIP::Recipes::Analysis::Fastqc qw{ analysis_fastqc };
    use MIP::Recipes::Analysis::Freebayes qw { analysis_freebayes_calling };
    use MIP::Recipes::Analysis::Frequency_filter
      qw{ analysis_frequency_filter };
    use MIP::Recipes::Analysis::Gatk_baserecalibration
      qw{ analysis_gatk_baserecalibration analysis_gatk_baserecalibration_rio };
    use MIP::Recipes::Analysis::Gatk_combinevariantcallsets
      qw{ analysis_gatk_combinevariantcallsets };
    use MIP::Recipes::Analysis::Gatk_gathervcfs qw{ analysis_gatk_gathervcfs };
    use MIP::Recipes::Analysis::Gatk_genotypegvcfs
      qw{ analysis_gatk_genotypegvcfs };
    use MIP::Recipes::Analysis::Gatk_haplotypecaller
      qw{ analysis_gatk_haplotypecaller };
    use MIP::Recipes::Analysis::Gatk_variantevalall
      qw{ analysis_gatk_variantevalall };
    use MIP::Recipes::Analysis::Gatk_variantevalexome
      qw{ analysis_gatk_variantevalexome };
    use MIP::Recipes::Analysis::Gzip_fastq qw{ analysis_gzip_fastq };
    use MIP::Recipes::Analysis::Manta qw{ analysis_manta };
    use MIP::Recipes::Analysis::Markduplicates
      qw{ analysis_markduplicates analysis_markduplicates_rio };
    use MIP::Recipes::Analysis::Mip_vcfparser
      qw{ analysis_mip_vcfparser };
    use MIP::Recipes::Analysis::Multiqc qw{ analysis_multiqc };
    use MIP::Recipes::Analysis::Peddy qw{ analysis_peddy };
    use MIP::Recipes::Analysis::Picardtools_collecthsmetrics
      qw{ analysis_picardtools_collecthsmetrics };
    use MIP::Recipes::Analysis::Picardtools_collectmultiplemetrics
      qw{ analysis_picardtools_collectmultiplemetrics };
    use MIP::Recipes::Analysis::Picardtools_genotypeconcordance
      qw{ analysis_picardtools_genotypeconcordance };
    use MIP::Recipes::Analysis::Picardtools_mergesamfiles
      qw{ analysis_picardtools_mergesamfiles analysis_picardtools_mergesamfiles_rio };
    use MIP::Recipes::Analysis::Plink qw{ analysis_plink };
    use MIP::Recipes::Analysis::Prepareforvariantannotationblock
      qw{ analysis_prepareforvariantannotationblock };
    use MIP::Recipes::Analysis::Qccollect qw{ analysis_qccollect };
    use MIP::Recipes::Analysis::Rankvariant
      qw{ analysis_rankvariant analysis_rankvariant_unaffected analysis_rankvariant_sv analysis_rankvariant_sv_unaffected };
    use MIP::Recipes::Analysis::Rhocall
      qw{ analysis_rhocall_annotate };
    use MIP::Recipes::Analysis::Rtg_vcfeval qw{ analysis_rtg_vcfeval  };
    use MIP::Recipes::Analysis::Sacct qw{ analysis_sacct };
    use MIP::Recipes::Analysis::Sambamba_depth qw{ analysis_sambamba_depth };
    use MIP::Recipes::Analysis::Samtools_subsample_mt
      qw{ analysis_samtools_subsample_mt };
    use MIP::Recipes::Analysis::Split_fastq_file
      qw{ analysis_split_fastq_file };
    use MIP::Recipes::Analysis::Sv_annotate qw{ analysis_sv_annotate };
    use MIP::Recipes::Analysis::Sv_reformat qw{ analysis_reformat_sv };
    use MIP::Recipes::Analysis::Snpeff
      qw{ analysis_snpeff };
    use MIP::Recipes::Analysis::Sv_combinevariantcallsets
      qw{ analysis_sv_combinevariantcallsets };
    use MIP::Recipes::Analysis::Tiddit qw{ analysis_tiddit };
    use MIP::Recipes::Analysis::Variant_integrity
      qw{ analysis_variant_integrity };
    use MIP::Recipes::Analysis::Vcf2cytosure qw{ analysis_vcf2cytosure };
    use MIP::Recipes::Analysis::Vep qw{ analysis_vep };
    use MIP::Recipes::Analysis::Vt qw{ analysis_vt };
    use MIP::Recipes::Build::Rd_dna qw{build_rd_dna_meta_files};
    use MIP::Set::Analysis qw{ set_recipe_on_analysis_type set_rankvariants_ar };

    ### Pipeline specific checks
    check_rd_dna(
        {
            active_parameter_href           => $active_parameter_href,
            broadcasts_ref                  => $broadcasts_ref,
            file_info_href                  => $file_info_href,
            infile_both_strands_prefix_href => $infile_both_strands_prefix_href,
            infile_lane_prefix_href         => $infile_lane_prefix_href,
            log                             => $log,
            order_parameters_ref            => $order_parameters_ref,
            parameter_href                  => $parameter_href,
            sample_info_href                => $sample_info_href,
        }
    );

    ### Build recipes
    $log->info(q{[Reference check - Reference prerequisites]});

    build_rd_dna_meta_files(
        {
            active_parameter_href   => $active_parameter_href,
            file_info_href          => $file_info_href,
            infile_lane_prefix_href => $infile_lane_prefix_href,
            job_id_href             => $job_id_href,
            log                     => $log,
            parameter_href          => $parameter_href,
            sample_info_href        => $sample_info_href,
        }
    );

    ### Analysis recipes
    ## Create code reference table for pipeline analysis recipes
    my %analysis_recipe = (
        analysisrunstatus         => \&analysis_analysisrunstatus,
        bcftools_mpileup          => \&analysis_bcftools_mpileup,
        bwa_mem                   => \&analysis_bwa_mem,
        chanjo_sexcheck           => \&analysis_chanjo_sex_check,
        cnvnator                  => \&analysis_cnvnator,
        delly_call                => \&analysis_delly_call,
        delly_reformat            => \&analysis_delly_reformat,
        endvariantannotationblock => \&analysis_endvariantannotationblock,
        expansionhunter           => \&analysis_expansionhunter,
        evaluation                => \&analysis_picardtools_genotypeconcordance,
        fastqc                    => \&analysis_fastqc,
        freebayes                 => \&analysis_freebayes_calling,
        frequency_filter          => \&analysis_frequency_filter,
        gatk_baserecalibration    => \&analysis_gatk_baserecalibration,
        gatk_gathervcfs           => \&analysis_gatk_gathervcfs,
        gatk_combinevariantcallsets => \&analysis_gatk_combinevariantcallsets,
        gatk_genotypegvcfs          => \&analysis_gatk_genotypegvcfs,
        gatk_haplotypecaller        => \&analysis_gatk_haplotypecaller,
        gatk_variantevalall         => \&analysis_gatk_variantevalall,
        gatk_variantevalexome       => \&analysis_gatk_variantevalexome,
        gatk_variantrecalibration => undef,    # Depends on analysis type
        gzip_fastq                   => \&analysis_gzip_fastq,
        manta                        => \&analysis_manta,
        markduplicates               => \&analysis_markduplicates,
        multiqc                      => \&analysis_multiqc,
        peddy                        => \&analysis_peddy,
        picardtools_collecthsmetrics => \&analysis_picardtools_collecthsmetrics,
        picardtools_collectmultiplemetrics =>
          \&analysis_picardtools_collectmultiplemetrics,
        picardtools_mergesamfiles => \&analysis_picardtools_mergesamfiles,
        plink                     => \&analysis_plink,
        prepareforvariantannotationblock =>
          \&analysis_prepareforvariantannotationblock,
        qccollect   => \&analysis_qccollect,
        rankvariant => undef,                       # Depends on sample features
        rhocall     => \&analysis_rhocall_annotate,
        rtg_vcfeval => \&analysis_rtg_vcfeval,
        sacct       => \&analysis_sacct,
        sambamba_depth            => \&analysis_sambamba_depth,
        samtools_subsample_mt     => \&analysis_samtools_subsample_mt,
        snpeff                    => \&analysis_snpeff,
        split_fastq_file          => \&analysis_split_fastq_file,
        sv_annotate               => \&analysis_sv_annotate,
        sv_combinevariantcallsets => \&analysis_sv_combinevariantcallsets,
        sv_rankvariant => undef,                    # Depends on sample features
        sv_reformat    => \&analysis_reformat_sv,
        sv_varianteffectpredictor => undef,         # Depends on analysis type
        sv_vcfparser              => undef,         # Depends on analysis type
        tiddit                 => \&analysis_tiddit,
        varianteffectpredictor => \&analysis_vep,
        variant_integrity      => \&analysis_variant_integrity,
        vcfparser              => \&analysis_mip_vcfparser,
        vcf2cytosure           => \&analysis_vcf2cytosure,
        vt                     => \&analysis_vt,
    );

    ### Special case for '--rio' capable analysis recipes
    ## Define rio block programs and order
    my $is_bamcalibrationblock_done;
    my @order_bamcal_programs;
    my %bamcal_ar;
    _define_bamcalibration_ar(
        {
            active_parameter_href     => $active_parameter_href,
            bamcal_ar_href            => \%bamcal_ar,
            order_bamcal_programs_ref => \@order_bamcal_programs,
        }
    );

    ## Special case for rankvariants recipe
    set_rankvariants_ar(
        {
            analysis_recipe_href  => \%analysis_recipe,
            log                   => $log,
            parameter_href        => $parameter_href,
            sample_ids_ref => $active_parameter_href->{sample_ids},
        }
    );

    ## Update which recipe to use depending on consensus analysis type
    set_recipe_on_analysis_type(
        {
            analysis_recipe_href => \%analysis_recipe,
            consensus_analysis_type =>
              $parameter_href->{dynamic_parameter}{consensus_analysis_type},
        }
    );

  PROGRAM:
    foreach my $program ( @{$order_programs_ref} ) {

        ## Skip not active programs
        next PROGRAM if ( not $active_parameter_href->{$program} );

        ## Skip program if not part of dispatch table (such as gzip_fastq)
        next PROGRAM if ( not $analysis_recipe{$program} );

        ## Skip program if bamcalibration block is done
        ## and program is part of bamcalibration block
        next PROGRAM
          if ( $is_bamcalibrationblock_done
            and any { $_ eq $program } @order_bamcal_programs );

        ### Analysis recipes
        ## rio enabled and bamcalibration block analysis recipe
        if ( $active_parameter_href->{reduce_io}
            and any { $_ eq $program } @order_bamcal_programs )
        {

            ## For displaying
            log_display_program_for_user(
                {
                    log     => $log,
                    program => q{bamcalibrationblock},
                }
            );

            analysis_bamcalibrationblock(
                {
                    active_parameter_href   => $active_parameter_href,
                    bamcal_ar_href          => \%bamcal_ar,
                    file_info_href          => $file_info_href,
                    infile_lane_prefix_href => $infile_lane_prefix_href,
                    job_id_href             => $job_id_href,
                    log                     => $log,
                    order_programs_ref      => \@order_bamcal_programs,
                    parameter_href          => $parameter_href,
                    program_name            => q{bamcalibrationblock},
                    sample_info_href        => $sample_info_href,
                }
            );

            ## Done with bamcalibration block
            $is_bamcalibrationblock_done = 1;
        }
        else {

            ## For displaying
            log_display_program_for_user(
                {
                    log     => $log,
                    program => $program,
                }
            );
            ## Sample mode
            if ( $parameter_href->{$program}{analysis_mode} eq q{sample} ) {

              SAMPLE_ID:
                foreach
                  my $sample_id ( @{ $active_parameter_href->{sample_ids} } )
                {

                    $analysis_recipe{$program}->(
                        {
                            active_parameter_href   => $active_parameter_href,
                            file_info_href          => $file_info_href,
                            infile_lane_prefix_href => $infile_lane_prefix_href,
                            job_id_href             => $job_id_href,
                            parameter_href          => $parameter_href,
                            program_name            => $program,
                            sample_id               => $sample_id,
                            sample_info_href        => $sample_info_href,
                        }
                    );
                }
            }

            ## Family mode
            elsif ( $parameter_href->{$program}{analysis_mode} eq q{family} ) {

                $analysis_recipe{$program}->(
                    {
                        active_parameter_href   => $active_parameter_href,
                        file_info_href          => $file_info_href,
                        infile_lane_prefix_href => $infile_lane_prefix_href,
                        job_id_href             => $job_id_href,
                        parameter_href          => $parameter_href,
                        program_name            => $program,
                        sample_info_href        => $sample_info_href,
                    }
                );
            }

            ## Special case
            exit if ( $program eq q{split_fastq_file} );
        }
    }
    return;
}

sub _define_bamcalibration_ar {

## Function : Define bamcalibration recipes, order, coderefs and activate
## Returns  :
## Arguments: $active_parameter_href     => Active parameters for this analysis hash {REF}
##          : $order_bamcal_programs_ref => Order of programs in bamcalibration block {REF}
##          : $bamcal_ar_href            => Bamcalibration analysis recipe hash {REF}

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $active_parameter_href;
    my $order_bamcal_programs_ref;
    my $bamcal_ar_href;

    my $tmpl = {
        active_parameter_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$active_parameter_href,
            strict_type => 1,
        },
        order_bamcal_programs_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$order_bamcal_programs_ref,
            strict_type => 1,
        },
        bamcal_ar_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$bamcal_ar_href,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    ## Define rio blocks programs and order
    @{$order_bamcal_programs_ref} = qw{ picardtools_mergesamfiles
      markduplicates
      gatk_baserecalibration
    };

    %{$bamcal_ar_href} = (
        gatk_baserecalibration    => \&analysis_gatk_baserecalibration_rio,
        markduplicates            => \&analysis_markduplicates_rio,
        picardtools_mergesamfiles => \&analysis_picardtools_mergesamfiles_rio,
    );

    ## Enable bamcalibration as analysis recipe
    $active_parameter_href->{bamcalibrationblock} = 1;

    if ( $active_parameter_href->{dry_run_all} ) {

        ## Dry run
        $active_parameter_href->{bamcalibrationblock} = 2;
    }
    return;
}

1;