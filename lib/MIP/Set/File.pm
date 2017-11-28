package MIP::Set::File;

use Carp;
use charnames qw{ :full :short };
use Cwd qw(abs_path);
use English qw{ -no_match_vars };
use Params::Check qw{ check allow last_error };
use open qw{ :encoding(UTF-8) :std };
use strict;
use utf8;
use warnings;
use warnings qw{ FATAL utf8 };

## CPANM
use autodie qw{ :all };
use Readonly;

BEGIN {

    use base qw{ Exporter };
    require Exporter;

    # Set the version for version checking
    our $VERSION = 1.02;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK =
      qw{ set_file_suffix set_merged_infile_prefix set_absolute_path };
}

## Constants
Readonly my $NEWLINE => qq{\n};

sub set_file_suffix {

## Function : Set the current file suffix for this job id chain
## Returns  : $file_suffix
## Arguments: $file_suffix    => File suffix
##          : $job_id_chain   => Job id chain for program
##          : $parameter_href => Holds all parameters
##          : $suffix_key     => Suffix key

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $file_suffix;
    my $job_id_chain;
    my $parameter_href;
    my $suffix_key;

    my $tmpl = {
        file_suffix => {
            required    => 1,
            defined     => 1,
            strict_type => 1,
            store       => \$file_suffix,
        },
        job_id_chain => {
            required    => 1,
            defined     => 1,
            strict_type => 1,
            store       => \$job_id_chain,
        },
        parameter_href => {
            required    => 1,
            defined     => 1,
            default     => {},
            strict_type => 1,
            store       => \$parameter_href,
        },
        suffix_key => {
            required    => 1,
            defined     => 1,
            strict_type => 1,
            store       => \$suffix_key,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    $parameter_href->{$suffix_key}{$job_id_chain} = $file_suffix;

    return $file_suffix;
}

sub set_merged_infile_prefix {

## Function : Set the merged infile prefix for sample id
## Returns  :
## Arguments: $file_info_href       => File info hash {REF}
##          : $merged_infile_prefix => Merged infile prefix
##          : $sample_id            => Sample id

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $file_info_href;
    my $merged_infile_prefix;
    my $sample_id;

    my $tmpl = {
        file_info_href => {
            required    => 1,
            defined     => 1,
            default     => {},
            strict_type => 1,
            store       => \$file_info_href,
        },
        merged_infile_prefix => {
            required    => 1,
            defined     => 1,
            strict_type => 1,
            store       => \$merged_infile_prefix,
        },
        sample_id => {
            required    => 1,
            defined     => 1,
            strict_type => 1,
            store       => \$sample_id,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    $file_info_href->{$sample_id}{merged_infile} = $merged_infile_prefix;

    return;
}

sub set_absolute_path {

## Function : Find aboslute path for supplied path or croaks and exists if path does not exists
## Returns  : $path (absolute path)
## Arguments: $parameter_name => Parameter to be evaluated
##          : $path           => Supplied path to be updated/evaluated

    my ($arg_href) = @_;

    ##Flatten argument(s)
    my $parameter_name;
    my $path;

    my $tmpl = {
        parameter_name => {
            required    => 1,
            defined     => 1,
            strict_type => 1,
            store       => \$parameter_name,
        },
        path => { required => 1, defined => 1, store => \$path },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    ## For broadcasting later
    my $original_path = $path;

    ## Reformat to absolute path
    $path = abs_path($path);

    ## Something went wrong
    if ( not defined $path ) {

        croak(  q{Could not find absolute path for }
              . $parameter_name . q{: }
              . $original_path
              . q{. Please check the supplied path!} );
    }
    return $path;
}

1;
