#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use feature qw/say/;
#use Smart::Comments;
#use Data::Printer;
use Net::Twitter::Lite::WithAPIv1_1;
use Config::Pit;
use Time::Piece;
use IO::All -utf8;
use Digest::MD5 qw/md5_hex/;
use LWP::Simple qw/mirror/;
use XML::FeedPP;
use open qw/:utf8 :std/;


my $MENU_DIR       = './menu/';
my $CACHE_DIR      = './cache/';
my $HANKAKU_SPACE  = q{ };
my $FEED_URL       = 'http://www.jaist.ac.jp/cafe/feed/';
my $FIRST_ITEM_NUM = 0;

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

if ($mday != -1)
{
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
}

warn 'フィードのチェックに失敗しました' if check_feed() == -1;

exit;




sub fetch_menu
{
    my $t = localtime;

    my ($year, $month) = ( $t->year, $t->strftime("%m") );

    # ↓は本番ではコメントアウト
    #$month = '05';
    ### $year
    ### $month

    my $menu_file = "${MENU_DIR}${year}/${month}.txt";
    return -1 unless -f $menu_file;

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


sub check_feed
{
    my $cache = "${CACHE_DIR}feed.xml";

    my $cache_last_update = (stat($cache))[9];

    # もし新しければ上書きされる
    LWP::Simple::mirror($FEED_URL, $cache) or return -1;

    my $feed_last_update = (stat($cache))[9];

    ### $cache_last_update
    ### $feed_last_update

    if ($feed_last_update > $cache_last_update)
    {
        # フィードが更新されている
        my $feed = XML::FeedPP->new($cache);
        my $item = $feed->get_item($FIRST_ITEM_NUM); # 短時間（１日以内）に複数回更新されない想定なのに注意

        my $title =  $item->title;
        my $desc  =  $item->description;
        my $link  =  $item->link;

        my $feed_info = <<"EOS";
【JAIST Cafeteria】「${title}」${desc} $link
EOS

        $twit->update($feed_info);
    }
}
