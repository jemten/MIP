package MIP::Program::Variantcalling::Cufflinks;

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

## MIPs lib/
use MIP::Unix::Standard_streams qw{ unix_standard_streams };
use MIP::Unix::Write_to_file qw{ unix_write_to_file };

BEGIN {
    require Exporter;
    use base qw{ Exporter };

    # Set the version for version checking
    our $VERSION = 1.00;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw{ cufflinks };
}

## Constants
Readonly my $SPACE => q{ };

sub cufflinks {

## Function : Perl wrapper for Cufflinks.
## Returns  : @commands
## Arguments: $FILEHANDLE             => Filehandle to write to
##          : $gtf_path               => Input GTF file (this file should not be compressed!)
##          : $infile_path            => Input bam file  path
##          : $library_type           => Orientation and strandedness of the library (read the cufflinks manual for more  info)
##          : $outdir_path            => Output directory path
##          : $stderrfile_path        => Stderrfile path
##          : $stderrfile_path_append => Append stderr info to file path
##          : $stdoutfile_path        => Stdoutfile path
##          : $threads                => Number of threads

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $FILEHANDLE;
    my $gtf_path;
    my $infile_path;
    my $library_type;
    my $outdir_path;
    my $stderrfile_path;
    my $stderrfile_path_append;
    my $stdoutfile_path;

    ## Default(s)
    my $threads;

    my $tmpl = {
        FILEHANDLE => {
            store => \$FILEHANDLE,
        },
        gtf_path => {
            defined     => 1,
            required    => 1,
            store       => \$gtf_path,
            strict_type => 1,
        },
        infile_path => {
            defined     => 1,
            required    => 1,
            store       => \$infile_path,
            strict_type => 1,
        },
        library_type => {
            defined     => 1,
            store       => \$library_type,
            strict_type => 1,
        },
        outdir_path => {
            defined     => 1,
            required    => 1,
            store       => \$outdir_path,
            strict_type => 1,
        },
        stderrfile_path => {
            store       => \$stderrfile_path,
            strict_type => 1,
        },
        stderrfile_path_append => {
            store       => \$stderrfile_path_append,
            strict_type => 1,
        },
        stdoutfile_path => {
            store       => \$stdoutfile_path,
            strict_type => 1,
        },
        threads => {
            default     => 16,
            defined     => 1,
            store       => \$threads,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    ## Stores commands depending on input parameters
    my @commands = q{cufflinks};

    # Options
    push @commands, q{-g} . $SPACE . $gtf_path;
    push @commands, q{-o} . $SPACE . $outdir_path;
    push @commands, q{-p} . $SPACE . $threads;

    if ($library_type) {
        push @commands, q{--library-type} . $SPACE . $library_type;
    }

    push @commands, $infile_path;

    push @commands,
      unix_standard_streams(
        {
            stderrfile_path        => $stderrfile_path,
            stderrfile_path_append => $stderrfile_path_append,
            stdoutfile_path        => $stdoutfile_path,
        }
      );

    unix_write_to_file(
        {
            commands_ref => \@commands,
            FILEHANDLE   => $FILEHANDLE,
            separator    => $SPACE,

        }
    );
    return @commands;

}

1;
