package Net::SSH::Perl::Cipher::AES_CTR;

use strict;

use Net::SSH::Perl::Cipher;
use base qw( Net::SSH::Perl::Cipher );

use Net::SSH::Perl::Cipher::CTR;
use Crypt::OpenSSL::AES;

sub new {
    my $class = shift;
    my $ciph = bless { }, $class;
    $ciph->init(@_) if @_;
    $ciph;
}

sub keysize { } # stub
sub blocksize { 16 } # 128 bits as required by AES

sub init {
    my $ciph = shift;
    my($key, $iv, $is_ssh2) = @_;
    $ciph->{is_ssh2} = defined $is_ssh2 ? $is_ssh2 : 0;

    $key = substr($key,0,$ciph->keysize);
    if ($is_ssh2) {
        my $aes = Crypt::OpenSSL::AES->new($key);
	$ciph->{ctr} = Net::SSH::Perl::Cipher::CTR->new($aes, $iv);
    }
}

sub encrypt {
    my($ciph, $text) = @_;
    if ($ciph->{is_ssh2}) {
        return $ciph->{ctr}->encrypt($text);
    }
}

sub decrypt {
    my($ciph, $text) = @_;
    if ($ciph->{is_ssh2}) {
        return $ciph->{ctr}->decrypt($text);
    }
}

1;
__END__

=head1 NAME

Net::SSH::Perl::Cipher::AES - Base class for AES support using
CTR (counter) mode.

=head1 SYNOPSIS

    use Net::SSH::Perl::Cipher;
    my $cipher = Net::SSH::Perl::Cipher->new('AES128_CTR', $key);
    print $cipher->encrypt($plaintext);

=head1 DESCRIPTION

I<Net::SSH::Perl::Cipher::AES_CTR> provides AES encryption
base class support for I<Net::SSH::Perl>. 

=head1 AUTHOR & COPYRIGHTS

Lance Kinley E<lkinley@loyaltymethods.com>

Copyright (c) 2015 Loyalty Methods, Inc.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
