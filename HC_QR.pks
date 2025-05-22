create or replace NONEDITIONABLE package hc_qr as

subtype t_eclevel_type      is varchar2(1);

c_eclevel_type_low          constant t_eclevel_type := 'L';
c_eclevel_type_medium       constant t_eclevel_type := 'M';
c_eclevel_type_quartile     constant t_eclevel_type := 'Q';
c_eclevel_type_high         constant t_eclevel_type := 'H';

c_default_foreground_color  constant varchar2(7)    := '#000000';
c_default_background_color  constant varchar2(7)    := '#FFFFFF';
c_default_quiet             constant number         := 1;
c_default_eclevel           constant t_eclevel_type := c_eclevel_type_high;
--c_default_margin            constant number         := 2;
c_default_max_input_length  constant number         := 4000;


c_default_scale             constant number         := 1;

function get_qrcode_png(
    p_value             in varchar2,
    p_scale             in number         default c_default_scale,
    p_quiet             in number         default c_default_quiet,
    p_eclevel           in t_eclevel_type default c_default_eclevel,
    p_foreground_color  in varchar2       default c_default_foreground_color,
    p_background_color  in varchar2       default null )
    return blob;

FUNCTION qr_base64(QR_TEXT IN VARCHAR2) RETURN VARCHAR2;

end hc_qr;
