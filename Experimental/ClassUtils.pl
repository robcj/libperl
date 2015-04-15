#!/usr/bin/perl -w


=head1 ClassUtils.pl

 Utilities to simplify the creation of accessor methods in perl modules
 These subroutines have to be part of your package, so load this using 
 "require" or "do"
 and a path to the ClassUtils.pl file.
 eg. require "Utilities/ClassUtils.pl"

 # Git Test 2

=cut

our $VERSION = 1.0;

##########
# Modules
##########

use strict;

##########
# Subs
##########

=head2 mkaccessors(@list)

 Creates accessor method for each name in the list.

=cut

sub mkaccessors {
    eval "sub $_ { getset(\@_) }" foreach @_ ;
}

=head2 mkGets(@list)

 Creates get method for each name in the list, as an alias to the accessor method as created by mkaccessors.
 Naming is automatically camelcase, eg.  organisation will become getOrganisation an alias for the organisation accessor.

=cut

sub mkGets {
    map {
      my $getter = 'get'.ucfirst($_);
      eval "sub $getter { $_(\@_) }" ;
    } @_;
}

=head2 mk_gets(@list)

 Creates get method for each name in the list, as an alias to the accessor method as created by mkaccessors.
 Naming is automatically undescore spaced, eg.  organisation will become get_organisation alias for the organisation accessor.

=cut

sub mk_gets {
    map {
      my $getter = "get_$_";
      eval "sub $getter { $_(\@_) }" ;
    } @_;
}

=head2 mkSets(@list)

 Creates set method for each name in the list, as an alias to the accessor method as created by mkaccessors.
 Naming is automatically camelcase, eg.  organisation will become setOrganisation alias for the organisation accessor.

=cut

sub mkSets {
    map {
      my $setter = 'set'.ucfirst($_);
      eval "sub $setter { $_(\@_) }" ;
    } @_;
}

=head2 mk_sets(@list)

 Creates set method for each name in the list, as an alias to the accessor method as created by mkaccessors.
 Naming is automatically undescore spaced, eg.  organisation will become set_organisation alias for the organisation accessor.

=cut

sub mk_sets {
    map {
      my $setter = "set_$_";
      eval "sub $setter { $_(\@_) }" ;
    } @_;
}

=head2 mkgetsets(@list)

 Wrapper for mkaccessors, mkGets and mkSets.
 Creates accessor plus camelcase set and get methods for each name in the list.

=cut

sub mkgetsets {
    mkaccessors(@_);
    mkGets(@_);
    mkSets(@_);
}

=head2 mk_get_sets(@list)

 Wrapper for mkaccessors, mk_gets and mk_sets.
 Creates accessor plus underscore spaced set and get methods for each name in the list.

=cut

sub mk_get_sets {
    mkaccessors(@_);
    mk_gets(@_);
    mk_sets(@_);
}

=head2 getset(@_)

 This is called by the accessor method.  It detects the caller method name and performs the standard accessor functions.
 ie. sets the method's same-named property if a parameter is passed, if no parameter is passed it returns the method's same-named property's value.

=cut

sub getset {
  my $caller = ((caller(1))[3] =~ /::([^:]+)$/)[0] ;
  $_[0]->{$caller} = $_[1] if defined $_[1];
  $_[0]->{$caller};
}

sub addTo {
  my $caller = ((caller(1))[3] =~ /::([^:]+)$/)[0] ;
  push @{$_[0]->{$caller}}, $_[1] if defined $_[1] ;
  
}

1;
__END__

=head1 NAME

 Utilities::ClassUtils

=head1 SYNOPSIS

 use Utilities::ClassUtils;
 mkgetsets( qw(sub1 sub2) );

=head2 Default Exports

 mkgetsets()

=head2 Optional Exports

 getset()

=head3 Description

 Simplifies the creation of Accessors/get-setter methods for OO modules.
 Just provide the method (subroutine) names in a list to the mkgetsets subroutine and it will
 generate a standard accessor method for each name.

=head3 Accessors/get-setter methods

 user
 setUser
 getUser
 host
 setHost
 getHost
 dir
 chdir / cd / setDir
 pwd / getDir

=head3 Utility methods

 shCmd
 plCmd


