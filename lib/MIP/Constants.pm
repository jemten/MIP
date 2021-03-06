package MIP::Constants;

use 5.026;
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

BEGIN {
    require Exporter;
    use base qw{ Exporter };

    # Set the version for version checking
    our $VERSION = 1.02;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw{
      $AMPERSAND
      %ANALYSIS
      $ASTERISK
      $CLOSE_BRACE
      $CLOSE_BRACKET
      $COLON
      $COMMA
      $DASH
      $DOLLAR_SIGN
      $DOT
      $DOUBLE_QUOTE
      $EMPTY_STR
      $ESCAPE
      $FORWARD_SLASH
      $MIP_VERSION
      $NEWLINE
      $OPEN_BRACE
      $OPEN_BRACKET
      $PIPE
      $SEMICOLON
      $SINGLE_QUOTE
      $SPACE
      $TAB
      $UNDERSCORE
    };
}

## Constants
## Set MIP version
## Constants
Readonly our $MIP_VERSION => q{v7.0.1};

## Symbols
Readonly our $AMPERSAND     => q{&};
Readonly our $ASTERISK      => q{*};
Readonly our $CLOSE_BRACE   => q{\}};
Readonly our $CLOSE_BRACKET => q{]};
Readonly our $COLON         => q{:};
Readonly our $COMMA         => q{,};
Readonly our $DASH          => q{-};
Readonly our $DOLLAR_SIGN   => q{$};
Readonly our $DOT           => q{.};
Readonly our $DOUBLE_QUOTE  => q{"};
Readonly our $EMPTY_STR     => q{};
Readonly our $ESCAPE        => q{\\};
Readonly our $FORWARD_SLASH => q{/};
Readonly our $NEWLINE       => qq{\n};
Readonly our $OPEN_BRACE    => q{\{};
Readonly our $OPEN_BRACKET  => q{[};
Readonly our $PIPE          => q{|};
Readonly our $SEMICOLON     => q{;};
Readonly our $SINGLE_QUOTE  => q{'};
Readonly our $SPACE         => q{ };
Readonly our $TAB           => qq{\t};
Readonly our $UNDERSCORE    => q{_};

## Analysis
Readonly our %ANALYSIS => (
    ANNOTATION_DISTANCE    => 5000,
    ANNOTATION_DISTANCE_MT => 0,
);

1;
