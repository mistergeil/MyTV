// MyTV channel list — add a channel by adding one entry.
//   number: channel number shown on screen
//   name / short: display name / short label for the list
//   logo:   optional image URL ("" = show short name)
//   type:   "hls"      → official HLS stream (.m3u8), plays inside MyTV
//           (omitted)  → iframe embed
//   geo:    true / "CH" / "AT" → only available in Germany / Switzerland / Austria (VPN switches automatically)
//   epg:    channel id in the ARD program API (programm-api.ard.de) → program guide
//   xmltv:  channel id in data/epg.json (built every 6 h by .github/workflows/epg.yml from epgshare01)
//   mode:   "external" → provider blocks embedding; opens its player in a new tab
// Tested from Canada on 2026-10-02.
window.CHANNELS = [
  { number: 1,  name: "Das Erste",    short: "ARD",   mode: "external", geo: true, epg: "daserste", url: "https://www.joyn.de/play/live-tv?channel_id=165" },   // official HLS: https://daserste-live.ard-mcdn.de/daserste/live/hls/int/master.m3u8
  { number: 2,  name: "ZDF",          short: "ZDF",   type: "hls", geo: true, xmltv: "ZDF.de", url: "https://zdf-hls-15.akamaized.net/hls/live/2016498/de/high/master.m3u8" },
  { number: 3,  name: "tagesschau24", short: "TS24",  type: "hls", epg: "tagesschau24", url: "https://tagesschau.akamaized.net/hls/live/2020115/tagesschau/tagesschau_1/master.m3u8" },
  { number: 4,  name: "phoenix",      short: "phx",   type: "hls", geo: true, epg: "phoenix", url: "https://zdf-hls-19.akamaized.net/hls/live/2016502/de/high/master.m3u8" },
  { number: 5,  name: "3sat",         short: "3sat",  type: "hls", geo: true, epg: "3sat", url: "https://zdf-hls-18.akamaized.net/hls/live/2016501/dach/high/master.m3u8" },
  { number: 6,  name: "arte",         short: "arte",  type: "hls", geo: true, epg: "arte", url: "https://artesimulcast.akamaized.net/hls/live/2030993/artelive_de/index.m3u8" },
  { number: 7,  name: "ZDFneo",       short: "neo",   type: "hls", geo: true, xmltv: "ZDFneo.de", url: "https://zdf-hls-16.akamaized.net/hls/live/2016499/de/high/master.m3u8" },
  { number: 8,  name: "ZDFinfo",      short: "info",  type: "hls", geo: true, xmltv: "ZDFinfo.de", url: "https://zdf-hls-17.akamaized.net/hls/live/2016500/de/high/master.m3u8" },
  { number: 9,  name: "ONE",          short: "ONE",   type: "hls", geo: true, epg: "one", url: "https://mcdn-one.ard.de/ardone/hls/master.m3u8" },
  { number: 10, name: "ARD alpha",    short: "alpha", type: "hls", epg: "alpha", url: "https://mcdn.br.de/br/fs/ard_alpha/hls/de/master.m3u8" },
  { number: 11, name: "KiKA",         short: "KiKA",  type: "hls", epg: "kika", url: "https://kikageohls.akamaized.net/hls/live/2022693/livetvkika_de/master.m3u8" },
  { number: 12, name: "WDR",          short: "WDR",   type: "hls", epg: "wdr", url: "https://wdrfs247.akamaized.net/hls/live/681509/wdr_msl4_fs247/index.m3u8" },
  { number: 13, name: "NDR",          short: "NDR",   type: "hls", epg: "ndr", url: "https://mcdn.ndr.de/ndr/hls/ndr_fs/ndr_hh/master.m3u8" },
  { number: 14, name: "BR",           short: "BR",    type: "hls", epg: "br", url: "https://mcdn.br.de/br/fs/bfs_sued/hls/de/master.m3u8" },
  { number: 15, name: "hr",           short: "HR",    type: "hls", epg: "hr", url: "https://hrhls.akamaized.net/hls/live/2024525/hrhls/master.m3u8" },
  { number: 16, name: "SR",           short: "SR",    type: "hls", epg: "sr", url: "https://srfs.akamaized.net/hls/live/689649/srfsgeo/index.m3u8" },
  { number: 17, name: "MDR",          short: "MDR",   type: "hls", geo: true, epg: "mdr", url: "https://mdrtvsnhls.akamaized.net/hls/live/2016928/mdrtvsn/master.m3u8" },
  { number: 18, name: "SWR",          short: "SWR",   type: "hls", geo: true, epg: "swr", url: "https://swrbwd-hls.akamaized.net/hls/live/2018672/swrbwd/master.m3u8" },
  { number: 19, name: "rbb",          short: "rbb",   type: "hls", geo: true, epg: "rbb", url: "https://rbb-hls-berlin.akamaized.net/hls/live/2017824/rbb_berlin/master.m3u8" },
  // Private channels: Joyn (official, free, Germany → VPN DE) where available, otherwise livehdtv
  { number: 20, name: "RTL",          short: "RTL",   mode: "external", geo: true, xmltv: "RTL.de", url: "https://plus.rtl.de/rtl/live" },
  { number: 21, name: "SAT.1",        short: "SAT.1", mode: "external", xmltv: "SAT.1.de", geo: true, url: "https://www.joyn.de/play/live-tv?channel_id=2" },
  { number: 22, name: "ProSieben",    short: "PRO7",  mode: "external", xmltv: "ProSieben.de", geo: true, url: "https://www.joyn.de/play/live-tv?channel_id=1" },
  { number: 23, name: "VOX",          short: "VOX",   mode: "external", geo: true, xmltv: "VOX.de", url: "https://plus.rtl.de/vox/live" },
  { number: 24, name: "kabel eins",   short: "kab1",  mode: "external", xmltv: "kabel.eins.de", geo: true, url: "https://www.joyn.de/play/live-tv?channel_id=3" },
  { number: 25, name: "RTLZWEI",      short: "RTL2",  mode: "external", geo: true, xmltv: "RTLZWEI.de", url: "https://plus.rtl.de/rtlzwei/live" },
  { number: 26, name: "ProSieben MAXX", short: "MAXX", mode: "external", xmltv: "ProSieben.MAXX.de", geo: true, url: "https://www.joyn.de/play/live-tv?channel_id=5" },
  { number: 27, name: "SAT.1 Gold", short: "Gold", mode: "external", xmltv: "SAT.1.Gold.de", geo: true, url: "https://www.joyn.de/play/live-tv?channel_id=6" },
  { number: 28, name: "sixx", short: "sixx", mode: "external", xmltv: "sixx.de", geo: true, url: "https://www.joyn.de/play/live-tv?channel_id=4" },
  { number: 29, name: "kabel eins Doku", short: "k1Dok", mode: "external", xmltv: "kabel.eins.Doku.de", geo: true, url: "https://www.joyn.de/play/live-tv?channel_id=7" },
  { number: 30, name: "Super RTL", short: "SRTL", mode: "external", geo: true, xmltv: "SUPER.RTL.de", url: "https://plus.rtl.de/super-rtl/live" },
  { number: 31, name: "RTL Nitro", short: "Nitro", mode: "external", geo: true, xmltv: "NITRO.de", url: "https://plus.rtl.de/nitro/live" },
  { number: 32, name: "n-tv", short: "n-tv", mode: "external", geo: true, xmltv: "ntv.de", url: "https://plus.rtl.de/ntv/live" },
  { number: 33, name: "WELT", short: "WELT", mode: "external", xmltv: "WELT.de", geo: true, url: "https://www.joyn.de/play/live-tv?channel_id=113" },
  { number: 34, name: "Tele 5", short: "Tele5", mode: "external", xmltv: "Tele.5.de", geo: true, url: "https://www.joyn.de/play/live-tv?channel_id=1026" },
  { number: 35, name: "DMAX", short: "DMAX", mode: "external", xmltv: "DMAX.de", geo: true, url: "https://www.joyn.de/play/live-tv?channel_id=110" },
  { number: 36, name: "TLC", short: "TLC", mode: "external", xmltv: "TLC.de", url: "https://www.livehdtv.net/embed/tlc-germany/" },
  { number: 37, name: "Comedy Central", short: "CC", mode: "external", xmltv: "Comedy.Central.de", url: "https://www.livehdtv.net/embed/comedy-central-germany/" },
  { number: 38, name: "Disney Channel", short: "Disny", mode: "external", xmltv: "Disney.Channel.de", url: "https://www.livehdtv.net/embed/disney-channel-germany/" },
  { number: 39, name: "Nickelodeon", short: "Nick", mode: "external", xmltv: "nick.de", url: "https://www.livehdtv.net/embed/ch474/" },
  { number: 40, name: "DW Deutsch", short: "DW", mode: "external", url: "https://www.livehdtv.net/embed/dw-deutsche-welle-deutsch/" },
  // Switzerland — SRG channels: official Play SRF/RTS/RSI embed page opened full-screen (kiosk) with MyTV overlay; Swiss IP needed → VPN CH
  { number: 41, name: "SRF 1",       short: "SRF1",  mode: "external", geo: "CH", xmltv: "SRF.1.ch",    url: "https://www.srf.ch/play/embed?autoplay=true&urn=urn:srf:video:c4927fcf-e1a0-0001-7edd-1ef01d441651" },
  { number: 42, name: "SRF zwei",    short: "SRF2",  mode: "external", geo: "CH", xmltv: "SRF.zwei.ch", url: "https://www.srf.ch/play/embed?autoplay=true&urn=urn:srf:video:c49c1d64-9f60-0001-1c36-43c288c01a10" },
  { number: 43, name: "SRF info",    short: "SRFi",  mode: "external", geo: "CH", xmltv: "SRF.info.ch", url: "https://www.srf.ch/play/embed?autoplay=true&urn=urn:srf:video:c49c1d73-2f70-0001-138a-15e0c4ccd3d0" },
  { number: 44, name: "RTS 1",       short: "RTS1",  mode: "external", geo: "CH", xmltv: "RTS.1.ch",    url: "https://www.rts.ch/play/embed?autoplay=true&urn=urn:rts:video:3608506" },
  { number: 45, name: "RTS 2",       short: "RTS2",  mode: "external", geo: "CH", xmltv: "RTS.2.ch",    url: "https://www.rts.ch/play/embed?autoplay=true&urn=urn:rts:video:3608517" },
  { number: 46, name: "RTS Info",    short: "RTSi",  mode: "external", geo: "CH",                       url: "https://www.rts.ch/play/embed?autoplay=true&urn=urn:rts:video:1967124" },
  { number: 47, name: "RSI LA 1",    short: "LA1",   mode: "external", geo: "CH", xmltv: "RSI.La.1.ch", url: "https://www.rsi.ch/play/embed?autoplay=true&urn=urn:rsi:video:livestream_La1" },
  { number: 48, name: "RSI LA 2",    short: "LA2",   mode: "external", geo: "CH", xmltv: "RSI.LA.2.ch", url: "https://www.rsi.ch/play/embed?autoplay=true&urn=urn:rsi:video:livestream_La2" },
  { number: 49, name: "Tele 1",      short: "Tele1", mode: "external", xmltv: "Tele.1.ch", url: "https://www.livehdtv.net/embed/tele-1-switzerland/" },
  { number: 50, name: "TeleTicino",  short: "TTi",   type: "hls", xmltv: "Tele.Ticino.ch", url: "https://vstream-cdn.ch/hls/teleticino.m3u8" },
  { number: 51, name: "Canal Alpha", short: "Alpha", type: "hls", url: "https://canalalphaju.vedge.infomaniak.com/livecast/ik:canalalphaju/playlist.m3u8" },
  { number: 52, name: "Canal 9",     short: "C9",    type: "hls", geo: "CH", xmltv: "Canal.9.ch", url: "https://livehd.vedge.infomaniak.com/livecast/livehd/master.m3u8" },
  // Austria — ORF ON official player page (Austrian IP needed → VPN AT), opened full-screen with MyTV overlay
  { number: 53, name: "ORF 1",   short: "ORF1", mode: "external", geo: "AT", xmltv: "ORF.1.at", url: "https://on.orf.at/live?channel=orf1" },
  { number: 54, name: "ORF 2",   short: "ORF2", mode: "external", geo: "AT", xmltv: "ORF.2.at", url: "https://on.orf.at/live?channel=orf2" },
  { number: 55, name: "ORF III", short: "ORF3", mode: "external", geo: "AT", xmltv: "ORF.3.at", url: "https://on.orf.at/live?channel=orf3" },
  // Sport
  { number: 56, name: "Eurosport 1", short: "ES1", mode: "external", geo: true, xmltv: "Eurosport.1.de", url: "https://www.joyn.de/play/live-tv?channel_id=122" },
  // RTL+ (Premium account, VPN DE)
  { number: 57, name: "RTLup",      short: "RTLup", mode: "external", geo: true, xmltv: "RTLup.de",     url: "https://plus.rtl.de/rtlup/live" },
  { number: 58, name: "VOXup",      short: "VOXup", mode: "external", geo: true, xmltv: "VOXup.de",     url: "https://plus.rtl.de/voxup/live" },
  { number: 59, name: "Toggo Plus", short: "Toggo", mode: "external", geo: true, xmltv: "TOGGO.plus.de", url: "https://plus.rtl.de/toggo-plus/live" },

  // YouTube channels: newest video first, then the next ones (list: data/youtube.json, built hourly by the GitHub Action)
  { number: 60, name: "Zarbex",     short: "ZRBX",  type: "youtube", yt: ["@zarbex", "@zarbexuncut", "v:Ybre8Q-iBWw", "UCqUkIkT0NvKxRQP-5_CMR3Q"] },
  { number: 61, name: "Gym",        short: "GYM",   type: "youtube", yt: ["@JesseJamesWest", "UCxiub44lXA3uQg_OaA9yheg", "@UrsKalecinski", "@WillTennyson", "@JeffNippard"] }
];
