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
use LWP::Simple qw/mirror get/;
use XML::FeedPP;
use Text::Truncate;
use Encode qw/decode_utf8 encode_utf8/;
use JSON;
use URI::Escape::XS qw/uri_escape/;
use open qw/:utf8 :std/;


my $MENU_DIR         = './menu/';
my $CACHE_DIR        = './cache/';
my $HANKAKU_SPACE    = q{ };
my $FEED_URL         = 'http://www.jaist.ac.jp/cafe/feed/';
my $FIRST_ITEM_NUM   = 0;
my $TWEET_MAX_STRLEN = 140;
my $BITLY_BASE_URL   = 'http://api.bit.ly/v3/shorten';

my $config = pit_get('JAIST_GOHAN', require => {
    'consumer_key'        => 'Input consumer_key',
    'consumer_secret'     => 'Input consumer_secret',
    'access_token'        => 'Input access_token',
    'access_token_secret' => 'Input access_token_secret',
    'bitly_user'          => 'Input bitly_user',
    'bitly_key'           => 'Input bitly_key',
});

my $twit = Net::Twitter::Lite::WithAPIv1_1->new(
    consumer_key        => $config->{consumer_key},
    consumer_secret     => $config->{consumer_secret},
    access_token        => $config->{access_token},
    access_token_secret => $config->{access_token_secret},
    ssl                 => 1,
);


#$twit->update('Hello, World!');

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

    tweet($menu);
}

warn 'フィードのチェックに失敗しました' if check_feed() == -1;
follow_and_remove(); # 自動相互フォロー

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

    my $cache_last_update = (stat($cache))[9] // 0;

    # もし新しければ上書きされる
    LWP::Simple::mirror($FEED_URL, $cache) or return -1;

    my $feed_last_update = (stat($cache))[9] // 0;

    ### $cache_last_update
    ### $feed_last_update

    if ($feed_last_update > $cache_last_update)
    {
        # フィードが更新されている
        my $feed = XML::FeedPP->new($cache);
        my $item = $feed->get_item($FIRST_ITEM_NUM); # 短時間（１日以内）に複数回更新されない想定なのに注意

        my $title = decode_utf8 $item->title;
        my $desc  = decode_utf8 $item->description;
        my $link  = decode_utf8 $item->link;

        if ($desc =~ /(http:[^\s]+\.pdf)/)
        {
            my $url = shorten_URL($1);
            $desc =~ s/http:[^\s]+\.pdf/$url/;
        }

        $link = shorten_URL($link);

        ### $title
        ### $desc
        ### $link

        my $feed_info = <<"EOS";
【JAIST Cafeteria】「${title}」${desc} $link
EOS

        ### $feed_info
        tweet($feed_info);
    }
}


sub tweet
{
    my ($text) = @_;

    $text = truncstr($text, $TWEET_MAX_STRLEN);

    $twit->update($text);
}


sub shorten_URL
{
    my $url      = uri_escape(shift);
    my $apiurl   = "${BITLY_BASE_URL}?login=%s&apiKey=%s&longUrl=%s&format=json";
    my $bitly    = sprintf($apiurl, $config->{bitly_user}, $config->{bitly_key}, $url);
    my $json     = LWP::Simple::get($bitly);
    my $res      = decode_json($json);
    my $shortURL = $res->{data}{url};

    return $shortURL;
}


sub follow_and_remove
{
    my $friends   = $twit->friends_ids;
    my $followers = $twit->followers_ids;

    my %ids = map +( $_ => 1 ), @{ $friends->{ids} }; # 差分を抽出

    for my $id (@{ $followers->{ids} })
    {
        my $result = delete $ids{$id};

        # 未フォローユーザをフォロー
        unless (defined $result)
        {
            eval { $twit->create_friend({ user_id => $id }) };
        }
    }

    # 残りはリムーブすべきユーザ
    for my $id (keys %ids)
    {
        eval { $twit->destroy_friend({ user_id => $id }) };
    }
}
