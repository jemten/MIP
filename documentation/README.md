# MIP - Mutation Identification Pipeline

[![Build Status](https://travis-ci.org/Clinical-Genomics/MIP.svg?branch=develop)](https://travis-ci.org/Clinical-Genomics/MIP)
[![Coverage Status](https://coveralls.io/repos/github/Clinical-Genomics/MIP/badge.svg?branch=develop)](https://coveralls.io/github/Clinical-Genomics/MIP?branch=develop)  

MIP enables identification of potential disease causing variants from sequencing data.

# [![DOI](https://zenodo.org/badge/7667877.svg)](https://zenodo.org/badge/latestdoi/7667877)

## Citing MIP

```
Rapid pulsed whole genome sequencing for comprehensive acute diagnostics of inborn errors of metabolism
Stranneheim H, Engvall M, Naess K, Lesko N, Larsson P, Dahlberg M, Andeer R, Wredenberg A, Freyer C, Barbaro M, Bruhn H, Emahazion T, Magnusson M, Wibom R, Zetterström RH, Wirta V, von Döbeln U, Wedell A.
BMC Genomics. 2014 Dec 11;15(1):1090. doi: 10.1186/1471-2164-15-1090.
PMID:25495354
```

## Overview

MIP performs whole genome or target region analysis of sequenced single-end and/or paired-end reads from the Illumina platform in fastq\(.gz\) format to generate annotated ranked potential disease causing variants.

MIP performs QC, alignment, coverage analysis, variant discovery and annotation, sample checks as well as ranking the found variants according to disease potential with a minimum of manual intervention. MIP is compatible with Scout for visualization of identified variants.

MIP rare disease DNA analyses single nucleotide variants (snvs), insertions and deletions (indels) and structural variants (SV).

MIP rare disease RNA analyses mono allelic expression, fusion transcripts, transcript expression and alternative splicing.

MIP rare disease DNA vcf rerun performs re-runs starting from bcfs.

MIP has been in use in the clinical production at the Clinical Genomics facility at Science for Life Laboratory since 2014.

## Example Usage
### MIP analyse rare disease DNA
```Bash
$ mip analyse rd_dna [case_id] --config_file [mip_config_dna.yaml] --pedigree_file [case_id_pedigree.yaml]
```

### MIP analyse rare disease DNA vcf rerun
```Bash
mip analyse rd_dna_vcf_rerun [case_id] --config_file [mip_config_dna_vcf_rerun.yaml] --vcf_rerun_file vcf.bcf  --sv_vcf_rerun_file sv_vcf.bcf --pedigree [case_id_pedigree_vcf_rerun.yaml]
```
### MIP analyse rare disease RNA
```Bash
$ mip analyse rd_rna [case_id] --config_file [mip_config_rna.yaml] --pedigree_file [case_id_pedigree_rna.yaml]
```
## Features

* Installation
  * Simple automated install of all programs using conda/SHELL via supplied install application
  * Downloads and prepares references in the installation process
  * Handle conflicting tool dependencies
* Autonomous
  * Checks that all dependencies are fulfilled before launching
  * Builds and prepares references and/or files missing before launching
  * Decompose and normalise reference\(s\) and variant vcf\(s\)
  * Splits and merges files/contigs for samples and case when relevant
* Automatic
  * A minimal amount of hands-on time
  * Tracks and executes all recipes without manual intervention
  * Creates internal queues at nodes to optimize processing
  * Minimal IO between nodes and login node
* Flexible:
  * Design your own workflow by turning on/off relevant recipes
  * Restart an analysis from anywhere in your workflow
  * Process one, or multiple samples using the recipe\(s\) of your choice
  * Supply parameters on the command line, in a pedigree.yaml file or via config files
  * Simulate your analysis before performing it
  * Redirect each recipe analysis process to a temporary directory \(@nodes or @login\)
  * Limit a run to a specific set of genomic intervals or chromosomes
  * Use multiple variant callers for both snv, indels and SV
  * Use multiple annotation programs
  * Optionally split data into clinical variants and research variants
* Fast
  * Analyses an exome trio in approximately 4 h
  * Analyses a genome in approximately 21 h
* Traceability
  * Track the status of each recipe through dynamically updated status logs
  * Recreate your analysis from the MIP log or generated config files
  * Log sample meta-data and sequence meta-data
  * Log version numbers of softwares and databases
  * Checks sample integrity \(sex, contamination, duplications, ancestry, inbreeding and relationship\)
  * Test data output existens and integrity using automated tests
* Annotation
  * Gene annotation
    * Summarize over all transcript and output on gene level
  * Transcript level annotation
    * Separate pathogenic transcripts for correct downstream annotation
  * Annotate all alleles for a position
    * Split multi-allelic records into single records to facilitate annotation
    * Left align and trim variants to normalise them prior to annotation
  * Extracts QC-metrics and stores them in YAML format
  * Annotate coverage across genetic regions via Sambamba and Chanjo
* Standardized
  * Use standard formats whenever possible
* Visualization
  * Ranks variants according to pathogenic potential
  * Output is directly compatible with [Scout](https://github.com/Clinical-Genomics/scout)

## Getting Started

### Installation

MIP is written in perl and therefore requires that perl is installed on your OS.

#### Prerequisites
* [Perl], version 5.26.0 or above
* [Cpanm](http://search.cpan.org/~miyagawa/App-cpanminus-1.7043/lib/App/cpanminus.pm)
* [Miniconda] version 4.5.11

We recommend perlbrew for installing and managing perl and cpanm libraries. Installation instructions and setting up specific cpanm libraries can be found [here](https://github.com/Clinical-Genomics/development/blob/master/docs/perl/installation/perlbrew.md).

#### Automated Installation \(Linux x86\_64\)
Below are instructions for installing MIP for analysis of rare diseases. Installation of the RNA pipeline follows a similar syntax.
##### 1.Clone the official git repository

```Bash
$ git clone https://github.com/Clinical-Genomics/MIP.git
$ cd MIP
```
##### 2.Install required perl modules from cpan

```Bash
$ cd definitions
$ cpanm --installdeps .
$ cd -
```  

##### 3.Test conda and mip installation files (optional)

```Bash
$ perl t/mip_install.test
```

##### 4.Create the install instructions for MIP
```Bash
$ perl mip install rd_dna
```
This will generate a bash script called "mip.sh" in your working directory.

###### *Note:*
  The batch script will attempt to install the MIP dependencies in a conda environment called MIP_rare. Some programs does not play nicely together and are installed in separate conda environments. MIP will install the following environments by default:
  * MIP's base environment (named MIP_rare in the example above)
  * MIP_rare_ecnvnator
  * MIP_rare_edelly
  * MIP_rare_epeddy
  * MIP_rare_eperl_5.26
  * MIP_rare_epy3
  * MIP_rare_etiddit
  * MIP_rare_evep

It is possible to specify which environments to install using the ``--installations`` flag, as well as the names of the environments using the ``environment_name`` flag. E.g. ``--installations emip ecnvnator --environment_name emip=MIP ecnvnator=CNVNATOR``.   

  - For a full list of available options and parameters, run: ``$ perl mip install rd_dna --help``
  - For a full list of parameter defaults, run: ``$ perl mip install rd_dna --ppd``

##### 5.Run the bash script

```Bash
$ bash mip.sh
```
A conda environment will be created where MIP with most of its dependencies will be installed.

###### *Note:*
  Some references are quite large and will take time to download. You might want to run this using screen or tmux. Alternatively, the installation script can be submitted as a sbatch job if the flag ``--sbatch_mode`` is used when generating the installation script.

##### 6.Test your MIP installation (optional)

Make sure to activate your MIP conda base environment before executing prove.

```Bash
$ prove t -r
$ perl t/mip_analyse_rd_dna.test
```

###### When setting up your analysis config file
  In your config yaml file or on the command line you will have to supply the ``load_env`` parameter to activate the environment specific for the tool. Here is an example with three Python 3 tools in their own environment and Peddy, CNVnator and VEP in each own, with some extra initialization:

  ```Yml
  load_env:
    MIP_rare:
     mip:
     method: conda
    MIP_rare_epy3:
     chanjo_sexcheck:
     genmod:
     method: conda
     multiqc_ar:
     rankvariant:
     sv_rankvariant:
     variant_integrity_ar:
    MIP_rare_ecnvnator:
     cnvnator_ar: "LD_LIBRARY_PATH=[CONDA_PATH]/lib/:$LD_LIBRARY_PATH; export LD_LIBRARY_PATH; source [CONDA_PATH]/envs/MIP_rare_ecnvnator/root/bin/thisroot.sh;"
     method: conda
    MIP_rare_edelly:
     delly_call:
     delly_reformat:
     method: conda
    MIP_rare_epeddy:
     peddy_ar:
     method: conda
    MIP_rare_evep:
     sv_varianteffectpredictor: "LD_LIBRARY_PATH=[CONDA_PATH]/envs/MIP_rare_evep/lib/:$LD_LIBRARY_PATH; export LD_LIBRARY_PATH;"
     varianteffectpredictor: "LD_LIBRARY_PATH=[CONDA_PATH]/envs/MIP_rare_evep/lib/:$LD_LIBRARY_PATH; export LD_LIBRARY_PATH;"
     method: conda
  ```

### Usage

MIP is called from the command line and takes input from the command line \(precedence\) or falls back on defaults where applicable.

Lists are supplied as repeated flag entries on the command line or in the config using the yaml format for arrays.  
Only flags that will actually be used needs to be specified and MIP will check that all required parameters are set before submitting to SLURM.

Recipe parameters can be set to "0" \(=off\), "1" \(=on\) and "2" \(=dry run mode\). Any recipe can be set to dry run mode and MIP will create sbatch scripts, but not submit them to SLURM. MIP can be restarted from any recipe using the ``--start_with_recipe`` flag.

MIP will overwrite data files when reanalyzing, but keeps all "versioned" sbatch scripts for traceability.

You can always supply `perl mip [process] [pipeline] --help` to list all available parameters and defaults.

Example usage:
```Bash
$ mip analyse rd_dna 3 --sample_ids 3-1-1A --sample_ids 3-2-1U --sample_ids 3-2-2U -pfqc 0 --bwa_mem 2 -c 3_config.yaml
```

This will analyse case 3 using 3 individuals from that case and begin the analysis with recipes after Bwa mem and use all parameter values as specified in the config file except those supplied on the command line, which has precedence.

#### Input

All references and template files should be placed directly in the reference directory specified by `--reference_dir`.

##### Meta-Data

* [Configuration file] \(YAML-format\)
* [Gene panel file]
* [Pedigree file] \(YAML-format\)
* [Rank model file] \(Ini-format; Snv/indel\)
* [SV rank model file] \(Ini-format; SV\)
* [Qc regexp file] \(YAML-format\)

#### Output

Analyses done per individual is found in each sample_id directory and analyses done including all samples can be found in the case directory.

##### Sbatch Scripts

MIP will create sbatch scripts \(.sh\) and submit them in proper order with attached dependencies to SLURM. These sbatch script are placed in the output script directory specified by `--outscript_dir`. The sbatch scripts are versioned and will not be overwritten if you begin a new analysis. Versioned "xargs" scripts will also be created where possible to maximize the use of the cores processing power.

##### Data

MIP will place any generated datafiles in the output data directory specified by `--outdata_dir`. All data files are regenerated for each analysis. STDOUT and STDERR for each recipe is written in the recipe/info directory.

[Configuration file]: https://github.com/Clinical-Genomics/MIP/blob/master/templates/mip_config.yaml
[Gene panel file]: https://github.com/Clinical-Genomics/MIP/blob/master/templates/aggregated_master.txt
[Miniconda]: http://conda.pydata.org/miniconda.html
[Pedigree file]: https://github.com/Clinical-Genomics/MIP/tree/master/templates/643594-miptest_pedigree.yaml
[Perl]:https://www.perl.org/
[Rank model file]: https://github.com/Clinical-Genomics/MIP/blob/master/templates/rank_model_cmms_-v1.23-.ini
[SV rank model file]: https://github.com/Clinical-Genomics/MIP/blob/master/templates/svrank_model_cmms_-v1.5-.ini
[Qc regexp file]: https://github.com/Clinical-Genomics/MIP/blob/master/templates/qc_regexp_-v1.19-.yaml
