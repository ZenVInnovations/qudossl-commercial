package OpenSSL::safe::installdata;

use strict;
use warnings;
use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(
    @PREFIX
    @libdir
    @BINDIR @BINDIR_REL_PREFIX
    @LIBDIR @LIBDIR_REL_PREFIX
    @INCLUDEDIR @INCLUDEDIR_REL_PREFIX
    @APPLINKDIR @APPLINKDIR_REL_PREFIX
    @ENGINESDIR @ENGINESDIR_REL_LIBDIR
    @MODULESDIR @MODULESDIR_REL_LIBDIR
    @PKGCONFIGDIR @PKGCONFIGDIR_REL_LIBDIR
    @CMAKECONFIGDIR @CMAKECONFIGDIR_REL_LIBDIR
    $COMMENT $VERSION @LDLIBS
);

our $COMMENT                    = '';
our @PREFIX                     = ( '/Users/venkateshpulimamidi/qudosslwork/qudossl-commercial-install' );
our @libdir                     = ( '/Users/venkateshpulimamidi/qudosslwork/qudossl-commercial-install/lib' );
our @BINDIR                     = ( '/Users/venkateshpulimamidi/qudosslwork/qudossl-commercial-install/bin' );
our @BINDIR_REL_PREFIX          = ( 'bin' );
our @LIBDIR                     = ( '/Users/venkateshpulimamidi/qudosslwork/qudossl-commercial-install/lib' );
our @LIBDIR_REL_PREFIX          = ( 'lib' );
our @INCLUDEDIR                 = ( '/Users/venkateshpulimamidi/qudosslwork/qudossl-commercial-install/include' );
our @INCLUDEDIR_REL_PREFIX      = ( 'include' );
our @APPLINKDIR                 = ( '/Users/venkateshpulimamidi/qudosslwork/qudossl-commercial-install/include/openssl' );
our @APPLINKDIR_REL_PREFIX      = ( 'include/openssl' );
our @ENGINESDIR                 = ( '/Users/venkateshpulimamidi/qudosslwork/qudossl-commercial-install/lib/engines-3' );
our @ENGINESDIR_REL_LIBDIR      = ( 'engines-3' );
our @MODULESDIR                 = ( '/Users/venkateshpulimamidi/qudosslwork/qudossl-commercial-install/lib/ossl-modules' );
our @MODULESDIR_REL_LIBDIR      = ( 'ossl-modules' );
our @PKGCONFIGDIR               = ( '/Users/venkateshpulimamidi/qudosslwork/qudossl-commercial-install/lib/pkgconfig' );
our @PKGCONFIGDIR_REL_LIBDIR    = ( 'pkgconfig' );
our @CMAKECONFIGDIR             = ( '/Users/venkateshpulimamidi/qudosslwork/qudossl-commercial-install/lib/cmake/OpenSSL' );
our @CMAKECONFIGDIR_REL_LIBDIR  = ( 'cmake/OpenSSL' );
our $VERSION                    = '3.5.7';
our @LDLIBS                     =
    # Unix and Windows use space separation, VMS uses comma separation
    $^O eq 'VMS'
    ? split(/ *, */, ' ')
    : split(/ +/, ' ');

1;
