package MIP::Recipes::Install::Pip;

use strict;
use warnings;
use warnings qw{ FATAL utf8 };
use utf8;
use open qw{ :encoding(UTF-8) :std };
use charnames qw{ :full :short };
use Carp;
use English qw{ -no_match_vars };
use Params::Check qw{ check allow last_error };
use Readonly;

## Constants
Readonly my $SPACE   => q{ };
Readonly my $NEWLINE => qq{\n};

BEGIN {

    require Exporter;
    use base qw{ Exporter };

    # Set the version for version checking
    our $VERSION = 1.0.3;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw{ install_pip_packages };

}

sub install_pip_packages {

## Function  : Recipe for install pip package(s).
## Returns   :
## Arguments : $conda_env         => Name of conda environment
##           : $FILEHANDLE        => Filehandle to write to
##           : $pip_packages_href => Hash with pip packages and their version numbers {REF}
##           : $quiet             => Optionally turn on quiet output
##           : $verbose           => Log debug messages

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $conda_env;
    my $FILEHANDLE;
    my $pip_packages_href;
    my $quiet;
    my $verbose;

    my $tmpl = {
        conda_env => {
            store       => \$conda_env,
            strict_type => 1,
        },
        FILEHANDLE => {
            required => 1,
            store    => \$FILEHANDLE,
        },
        pip_packages_href => {
            default => {},
            store   => \$pip_packages_href,
        },
        quiet => {
            allow       => [ undef, 0, 1 ],
            store       => \$quiet,
            strict_type => 1,
        },
        verbose => {
            allow => [ undef, 0, 1 ],
            store => \$verbose
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    ## Local modules
    use MIP::Log::MIP_log4perl qw{ retrieve_log };
    use MIP::Package_manager::Conda qw{ conda_activate conda_deactivate };
    use MIP::Package_manager::Pip qw{ pip_install };

    ## Return if no packages are to be installed
    return if not keys %{$pip_packages_href};

    ## Retrieve logger object
    my $log = retrieve_log(
        {
            log_name => q{mip_install::install_pip_packages},
            quiet    => $quiet,
            verbose  => $verbose,
        }
    );

    $log->info(q{Writing install instructions for pip packages});
    say {$FILEHANDLE} q{### Install PIP packages};

    ## Install PIP packages in conda environment
    if ($conda_env) {
        say {$FILEHANDLE} q{## Install PIP packages in conda environment:} . $SPACE
          . $conda_env;

        ## Activate conda environment
        conda_activate(
            {
                env_name   => $conda_env,
                FILEHANDLE => $FILEHANDLE,
            }
        );
        say {$FILEHANDLE} $NEWLINE;
    }
    else {
        say {$FILEHANDLE} q{### Install PIP packages in conda main environment};
    }

    ## Create an array for pip packages that are to be installed from provided hash
    my @packages = _create_package_array(
        {
            package_href              => $pip_packages_href,
            package_version_separator => q{==},
        }
    );

    ## Install PIP packages
    pip_install(
        {
            FILEHANDLE   => $FILEHANDLE,
            packages_ref => \@packages,
            quiet        => $quiet,
        }
    );
    say {$FILEHANDLE} $NEWLINE;

    ## Deactivate conda environment if conda_environment exists
    if ($conda_env) {
        say {$FILEHANDLE} q{## Deactivate conda environment};
        conda_deactivate(
            {
                FILEHANDLE => $FILEHANDLE,
            }
        );
        say {$FILEHANDLE} $NEWLINE;
    }
    print {$FILEHANDLE} $NEWLINE;
    return;

}

sub _create_package_array {

##Function  : Takes a reference to hash of packages and creates an array with
##          : package and version joined with a supplied separator if value is defined.
##          : Also checks that the version number makes sense
##Returns   : "@packages"
##Arguments : $package_href              => Hash with packages {REF}
##          : $package_version_separator => Scalar separating the package and the version

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $package_href;
    my $package_version_separator;

    my $tmpl = {
        package_href => {
            required    => 1,
            defined     => 1,
            default     => {},
            strict_type => 1,
            store       => \$package_href
        },
        package_version_separator => {
            required    => 1,
            defined     => 1,
            strict_type => 1,
            store       => \$package_version_separator
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    my @packages;

  PACKAGE:
    while ( my ( $package, $package_version ) = each %{$package_href} ) {
        if ( defined $package_version ) {

            # Check that the version number matches pattern
            if ( $package_version !~ qr/\d+.\d+ | \d+.\d+.\d+/xms ) {
                croak q{The version number does not match defiend pattern for }
                  . q{package: }
                  . $package
                  . $SPACE
                  . $package_version;
            }
            push @packages, $package . $package_version_separator . $package_version;
        }
        else {
            push @packages, $package;
        }
    }
    return @packages;
}

1;
