# Setup

## Fastq filename convention
The permanent filename should follow the following format:

``{LANE}_{DATE}_{FLOW-CELL}_{SAMPLE-ID}_{BARCODE-SEQ}_{DIRECTION 1/2}.fastq[.qz]``

Where some types or formats are required for each element:
- LANE = Integer
- DATE = YYMMDD
- BARCODE-SEQ = A, C, G, T or integer
- DIRECTION = 1 or 2

The `case_id` and `sample_id(s)` needs to be unique and the sample id supplied should be equal to the {SAMPLE_ID} in the filename.
Underscore cannot be part of any element in the file name as this is used as the separator for each element.

However, MIP will accept filenames in other formats as long as the filename contains the sample id and the mandatory information can be collected from the fastq header.

## Meta-Data
MIP requires pedigree information recorded in a pedigree.yaml file and a config file.

* [Pedigree file] \(YAML-format\)
* [Configuration file] \(YAML-format\)

## Dependencies
MIP comes with an install application, which will install all necessary programs to execute models in MIP via conda and/or $SHELL. Make sure you have installed all dependencies via the MIP install application and that you have loaded your MIP base environment.
You only need to install the dependencies that are required for the recipes that you want to run. If you have not installed a dependency for a module, MIP will tell you what dependencies you need to install and exit.

**Extra CPANM modules**
You can speed up, for instance, the Readonly module by also installing the companion module Readonly::XS. No change to the code is required and the Readonly module will call the Readonly::XS module if available.  

**CADD**
MIP is currently unable to install the CADD binary for dynamic calculation of indels and there is also no support for downloading the CADD references file. If you want to use these features in MIP you have to install and download them manually.

### **Programs**

- Simple Linux Utility for Resource Management ([SLURM]) (version: 18.08.0)

#### **Pipeline: Rare disease**
- [Bcftools] (version: 1.9)
- [BedTools] (version: 2.27.1)
- [BWA] (version: 0.7.15-1)
- [BWAKit] (version: 0.7.15)
- [CADD] (version: 1.4)
- [Chanjo] (version: 4.2.0)
- [Cnvnator] (version: 0.3.3)
- [Expansionhunter] (version 2.5.5)
- [Delly] (version: 0.7.8)
- [FastQC] (version: 0.11.8)
- [Freebayes] (version: 1.2.0)
- [GATK] (version: 3.8 and 4.0.11)
- [GENMOD] (version: 3.7.3)
- [Htslib] (version: 1.9)
- [Manta] (version: 1.4.0)
- [MultiQC] (version: 1.6)
- [Peddy] (version: 0.4.2)
- [PicardTools] (version: 2.18.14)
- [PLINK2] (version: 1.90b3x35)
- [rtg-tools] (version: 3.9.1)
- [Sambamba] (version: 0.6.8)
- [Samtools] (version: 1.9)
- [Stranger] (version: 0.4)
- [SnpEff] (version: 4.3.1)
- [Svdb] (version: 1.3.0)
- [Tiddit] (version: 2.3.1)
- [Variant_integrity] (version: 0.0.4)
- [Vcf2cytosure] (version: 0.4.3)
- [Vcfanno] (version: 0.3.1)
- [VEP] (version: 94) with plugin "ExACpLI", "MaxEntScan, LoFtool"
- [VT] (version: 20151110)

The version number after the software name are tested for compatibility with MIP.

### Databases/References

MIP can download many program prerequisites automatically via the mip download application ``mip download [PIPELINE]``.

MIP will build references and meta files (if required) prior to starting an analysis pipeline ``mip analyse [PIPELINE]``.

### **Automatic Build:**

Human Genome Reference Meta Files:
 1. The sequence dictionnary (".dict")
 2. The ".fasta.fai" file

BWA:
 1. The BWA index of the human genome.

Star:
 1. Star index files of the human genome

#### *Note*
If you do not supply these parameters (Bwa/Star) MIP will create these from scratch using the supplied human reference genom as template.

Capture target files:
 1. The "infile_list" and .pad100.infile_list files used in ``picardtools_collecthsmetrics``.
 2. The ".pad100.interval_list" file used by some GATK recipes.

#### *Note*
If you do not supply these parameters MIP will create these from scratch using the supplied "latest" supported capture kit ".bed" file and the supplied human reference genome as template.

[Bcftools]: http://www.htslib.org/
[BedTools]: http://bedtools.readthedocs.org/en/latest/
[BWA]: https://github.com/lh3/bwa
[BWAKit]: https://github.com/lh3/bwa/tree/master/bwakit
[CADD]: (https://github.com/kircherlab/CADD-scripts)
[Chanjo]: https://chanjo.readthedocs.org/en/latest/
[Cnvnator]: https://github.com/abyzovlab/CNVnator
[Configuration file]: https://github.com/henrikstranneheim/MIP/blob/master/templates/mip_config.yaml
[Expansionhunter]: https://github.com/Illumina/ExpansionHunter
[Delly]: https://github.com/dellytools/delly/
[FastQC]: http://www.bioinformatics.babraham.ac.uk/projects/fastqc/
[Freebayes]: https://github.com/ekg/freebayes
[GATK]: http://www.broadinstitute.org/gatk/
[GENMOD]: https://github.com/moonso/genmod/
[Htslib]: http://www.htslib.org/
[Manta]: https://github.com/Illumina/manta
[MultiQC]: https://github.com/ewels/MultiQC
[Peddy]: https://github.com/brentp/peddy
[Pedigree file]: https://github.com/Clinical-Genomics/MIP/tree/master/templates/643594-miptest_pedigree.yaml   
[PicardTools]: http://broadinstitute.github.io/picard/
[PLINK2]: https://www.cog-genomics.org/plink2
[rtg-tools]: https://github.com/RealTimeGenomics/rtg-tools
[Sambamba]: http://lomereiter.github.io/sambamba/
[Samtools]: http://www.htslib.org/
[SLURM]: http://slurm.schedmd.com/
[SnpEff]: http://snpeff.sourceforge.net/
[Stranger]: https://github.com/moonso/stranger
[Svdb]: https://github.com/J35P312/SVDB
[Tabix]: http://samtools.sourceforge.net/tabix.shtml
[Tiddit]: https://github.com/J35P312/TIDDIT
[Variant_integrity]: https://github.com/moonso/variant_integrity
[Vcf2cytosure]: https://github.com/NBISweden/vcf2cytosure
[Vcfanno]: https://github.com/brentp/vcfanno
[VEP]: https://github.com/Ensembl/ensembl-vep
[VT]: https://github.com/atks/vt
