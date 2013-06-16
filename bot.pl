#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use feature qw/say/;
use Net::Twitter::Lite::WithAPIv1_1;
use Config::Pit;


my $config = pit_get('JAIST_GOHAN', require => {
    'consumer_key'        => 'Input consumer_key',
    'consumer_secret'     => 'Input consumer_secret',
    'access_token'        => 'Input access_token',
    'access_token_secret' => 'Input access_token_secret',
});

my $twit = Net::Twitter::Lite::WithAPIv1_1->new(
    consumer_key        => $config->{consumer_key},
    consumer_secret     => $config->{consumer_secret},
    access_token        => $config->{access_token},
    access_token_secret => $config->{access_token_secret},
    ssl                 => 1,
);


$twit->update('Hello, World!');

