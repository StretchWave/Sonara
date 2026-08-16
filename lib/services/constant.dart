const domain = "https://music.youtube.com/";
const String baseUrl = '${domain}youtubei/v1/';
const fixedParms =
    '?prettyPrint=false&alt=json&key=AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';
// Fixed, real WEB_REMIX client version. Fabricating a date-based version
// (e.g. 1.<today>.01.00) makes YouTube treat the client as unknown and can
// serve degraded responses. This version is taken from the working
// MetroFuse (Metrolist) InnerTube client.
const clientVersion = "1.20260213.01.00";
const clientId = "67";
const userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0';
