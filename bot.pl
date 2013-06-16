#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use feature qw/say/;
#use Smart::Comments;
use Net::Twitter::Lite::WithAPIv1_1;
use Config::Pit;
use Time::Piece;
use IO::All -utf8;
use open qw/:utf8 :std/;


my $MENU_FOLDER   = './menu/';
my $HANKAKU_SPACE = q{ };

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


#$twit->updat e('Hello, World!');

my ($mday, $wday, $lunchA, $lunchB, $lunchC, $dinnerA, $dinnerB, $higawari_men, $original_plate)
    = fetch_menu();

my $menu = <<"EOS";
${mday}日（${wday}）のメニュー▼
　ランチＡ：$lunchA
　ランチＢ：$lunchB
　ランチＣ：$lunchC
ディナーＡ：$dinnerA
ディナーＢ：$dinnerB
日替わり麺：$higawari_men
オリジナル：$original_plate
EOS

$twit->update($menu);

exit;




sub fetch_menu
{
    my $t = localtime;

    my ($year, $month) = ( $t->year, $t->strftime("%m") );

    # ↓は本番ではコメントアウト
    $month = '05';
    ### $year
    ### $month

    my $menu_file = "${MENU_FOLDER}${year}/${month}.txt";
    exit unless -f $menu_file;

    my $content = io($menu_file)->slurp;
    $content =~ s/\n\n+/\n/g;
    $content =~ s/\n[^0-9]//g;

    # 4以下ならその日は食堂は休みと思われる
    my @lines = grep { length > 4 } split(/\n/, $content);

    for my $line (@lines)
    {
        chomp $line;

        my (
            $mday,    $wday,    $lunchA,       $lunchB,        $lunchC,
            $dinnerA, $dinnerB, $higawari_men, $original_plate
        )
        = split(/$HANKAKU_SPACE/o, $line);

        for ( ($mday, $wday, $lunchA, $lunchB, $lunchC, $dinnerA, $dinnerB, $higawari_men, $original_plate) )
        {
            $_ = 'なし' unless length $_;
        }

        if ($t->mday eq $mday)
        {
            return ($mday, $wday, $lunchA, $lunchB, $lunchC, $dinnerA, $dinnerB, $higawari_men, $original_plate);
        }
    }
}
