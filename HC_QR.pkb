create or replace NONEDITIONABLE PACKAGE BODY  hc_qr as
    
   type t_parameters is record (
       png_scale        number         default c_default_scale,
       foreground_color varchar2(7)    default c_default_foreground_color,
       background_color varchar2(7), 
       quiet            number         default c_default_quiet,
       eclevel          t_eclevel_type default c_default_eclevel,
       extended         boolean        default false,
       upper            boolean        default false,
       bearer           boolean        default false,
       checksum         boolean        default false
   );

   subtype t_barcode_type    is varchar2(10);
   subtype t_format_type     is varchar2(3);

   c_barcode_type_qr         constant t_barcode_type := 'QR';
   c_format_type_png         constant t_format_type  := 'PNG';

   type    tp_bits    is table of pls_integer index by pls_integer;
   type    tp_matrix  is table of tp_bits     index by pls_integer;

   function generate_png(
       p_data   in blob,
       p_width  in pls_integer,
       p_height in pls_integer,
       p_params in t_parameters )
       return raw
   is
       l_t_ihdr  raw(25);
       l_t_plte  raw(32);
       l_t_idat  raw(32767);
       l_t_trns  raw(32);

       function crc32(
           p_src in raw )
           return raw
       is
       begin
           return
               sys.utl_raw.reverse(
                   sys.utl_raw.substr(
                       sys.utl_raw.substr(
                           sys.utl_compress.lz_compress( p_src ), -8 ), 1, 4 ));
       end crc32;


      function method0_compress(
          p_val in blob )
          return raw
      is
          l_t_tmp raw(32767);

          function adler32(
              p_val in blob )
              return varchar2
          is
              l_s1    pls_integer := 1;
              l_s2    pls_integer := 0;
              l_t_val varchar2(32766);
              l_t_pos number      := 1;
              l_t_len number      := sys.dbms_lob.getlength( p_val );
          begin
              loop
                  exit when l_t_pos > l_t_len;
                  l_t_val := rawtohex( sys.dbms_lob.substr( p_val, 16383, l_t_pos ));
                  for i in 1 .. length( l_t_val ) / 2
                  loop
                      begin
                            l_s1 := l_s1 + to_number( substr( l_t_val, i * 2 - 1, 2 ), 'XX' );
                      exception
                          when others then
                              l_s1 := mod( l_s1, 65521 ) + to_number( substr( l_t_val, i * 2 - 1, 2 ), 'XX' );
                      end;
                      begin
                          l_s2 := l_s2 + l_s1;
                      exception
                          when others then
                              l_s2 := mod( l_s2, 65521 ) + l_s1;
                      end;
                  end loop;
                  l_t_pos := l_t_pos + 16383;
              end loop;
              l_s1 := mod( l_s1, 65521 );
              l_s2 := mod( l_s2, 65521 );
              return to_char( l_s2, 'fm0XXX' ) || to_char( l_s1, 'fm0XXX' );
          end adler32;
      begin
          l_t_tmp := sys.utl_compress.lz_compress( p_val );
          return sys.utl_raw.concat(
                  '789C',
                  sys.utl_raw.substr( l_t_tmp, 11, sys.utl_raw.length( l_t_tmp ) - 18 ),
                  adler32( p_val ));
      end method0_compress;

  begin
      l_t_ihdr := sys.utl_raw.concat(
                      '49484452', 
                      to_char( p_width, 'fm0XXXXXXX' ),
                      to_char( p_height, 'fm0XXXXXXX' ),
                      '0803000000' );  

      l_t_plte := sys.utl_raw.concat(
                      '504C5445', 
                      ltrim( coalesce( p_params.foreground_color, c_default_foreground_color ), '#' ),
                      ltrim( coalesce( p_params.background_color, c_default_background_color ), '#' ));

      if p_params.background_color is null then 
          l_t_trns := sys.utl_raw.concat(
                          '74524E53', 
                          'FF', 
                          '00' ); 
          l_t_trns := sys.utl_raw.concat(
                          '00000002', 
                          l_t_trns,
                          crc32( l_t_trns ));
      end if;

      l_t_idat := sys.utl_raw.concat(
                      '49444154', 
                      method0_compress( p_data ));

      return sys.utl_raw.concat(
                  '89504E470D0A1A0A', 
                  '0000000D',         
                  l_t_ihdr,
                  crc32( l_t_ihdr ),
                  '00000006',         
                  l_t_plte,
                  crc32( l_t_plte ),
                  l_t_trns,
                  to_char( sys.utl_raw.length( l_t_idat ) - 4, 'fm0XXXXXXX' ),
                  l_t_idat,
                  crc32( l_t_idat ),
                  '0000000049454E44AE426082' ); 
  exception
      when others then
          null;
  end generate_png;


  function bitxor(
      x in number,
      y in number )
      return number
  is
  begin
      return x + y - 2 * bitand( x, y );
  end bitxor;


  procedure append_bits(
      p_bits in out tp_bits,
      p_val  in number,
      p_cnt  in number )
  is
  begin
      for j in reverse 0 .. p_cnt - 1
      loop
          p_bits( p_bits.count ) := sign( bitand( p_val, power( 2, j )));
      end loop;
  end append_bits;


  function bitstoword(
      p_bits in tp_bits,
      p_sz   in pls_integer )
      return tp_bits
  is
      l_val   pls_integer;
      l_rv    tp_bits;
      l_first pls_integer := p_bits.first;
  begin
      for i in l_first ..  p_bits.count / p_sz - l_first - 1
      loop
          l_val := 0;
          for j in 0 .. p_sz - 1
          loop
              l_val := l_val * 2 + p_bits( l_first + ( i - l_first ) * p_sz + j );
          end loop;
          l_rv( i - l_first ) := l_val;
      end loop;
      return l_rv;
  end bitstoword;

  function reed_solomon(
      p_data      in tp_bits,
      p_primitive in pls_integer default 285,
      p_size      in pls_integer default 256,
      p_degree    in pls_integer default 16,
      p_b         in pls_integer default 1 )
      return tp_bits
  is
      type    tp_ecc is table of pls_integer index by pls_integer;
      l_t_exp tp_ecc;
      l_t_log tp_ecc;
      l_t_g   tp_ecc;
      l_t_ecc tp_ecc;
      l_t_x   pls_integer;
      l_t_rv  tp_bits;
  begin
      l_t_x := 1;
      for i in 0 .. p_size - 1
      loop
          l_t_exp( i ) := l_t_x;
          l_t_x      := l_t_x * 2;
          if l_t_x >= p_size then
              l_t_x    := bitand( p_size - 1, bitxor( p_primitive, l_t_x ));
          end if;
      end loop;
      for i in 0 .. p_size - 2
      loop
          l_t_log( l_t_exp( i ) ) := i;
      end loop;

      l_t_g(0) := 1;
      for i in 1 .. p_degree
      loop
          l_t_x    := i - 1 + p_b;
          l_t_g(i) := l_t_exp( mod( l_t_log( l_t_g( i-1 ) ) + l_t_x, p_size - 1 ) );
          for j in reverse 1 .. i - 1
          loop
              l_t_g(j) := bitxor( l_t_exp( mod( l_t_log( l_t_g( j - 1 )) + l_t_x, p_size - 1 )),
                                  l_t_g( j ));
          end loop;
      end loop;

      l_t_x := p_data.first;
      for i in l_t_x .. p_data.last
      loop
          l_t_ecc( i - l_t_x ) := p_data( i );
      end loop;

      for i in l_t_ecc.count .. l_t_ecc.count + p_degree - 1
      loop
          l_t_ecc( i ) := 0;
      end loop;

      while l_t_ecc.count >= l_t_g.count
      loop
          l_t_x := l_t_ecc( l_t_ecc.first );
          if l_t_x > 0 then
              for i in 0 .. l_t_g.count - 1
              loop
                  l_t_ecc( l_t_ecc.first + i ) := bitxor( l_t_ecc( l_t_ecc.first + i ),
                                                      l_t_exp( mod( l_t_log( l_t_g( i ) ) + l_t_log( l_t_x ), p_size - 1 )));
              end loop;
          end if;
          l_t_ecc.delete( l_t_ecc.first );
      end loop;

      l_t_x := l_t_ecc.first;
      for i in l_t_ecc.first .. l_t_ecc.last
      loop
          l_t_rv( i - l_t_x ) := l_t_ecc( i );
      end loop;
      return l_t_rv;
  end reed_solomon;

  procedure add_quiet(
      p_matrix in out nocopy tp_matrix,
      p_params in t_parameters,
      p_quiet  in pls_integer )
  is
      l_height pls_integer := p_matrix.count;
      l_width  pls_integer := p_matrix( p_matrix.first ).count;
      l_quiet  pls_integer;
  begin
      l_quiet := coalesce( p_params.quiet, p_quiet, 0 );
      if l_quiet = 0 then
          return;
      end if;

      for i in reverse 0 .. l_height - 1
      loop
          for j in reverse 0 .. l_width - 1
          loop
              p_matrix( i + l_quiet )( j + l_quiet ) := p_matrix(i)(j);
          end loop;
          for j in 0 .. l_quiet - 1
          loop
              p_matrix( i + l_quiet )(j) := 0;
              p_matrix( i + l_quiet )( j + l_width + l_quiet ) := 0;
          end loop;
      end loop;
      for j in 0 .. l_width + 2 * l_quiet - 1
      loop
          p_matrix(0)(j) := 0;
      end loop;
      for i in 0 .. l_quiet - 1
      loop
          p_matrix(i)                        := p_matrix(0);
          p_matrix( i + l_quiet + l_height ) := p_matrix(0);
      end loop;
  end add_quiet;


  procedure gen_qrcode_matrix(
      p_val    in varchar2 character set any_cs,
      p_params in t_parameters,
      p_matrix out tp_matrix )
  is
      l_version pls_integer;
      l_eclevel pls_integer;
      l_stream  tp_bits;
      l_tmp     raw(32767);
      l_sz      pls_integer;
      l_len     pls_integer;

      type tp_config     is table of pls_integer;
      type tp_ecc_config is table of tp_config;
      type tp_qr_config  is table of tp_ecc_config;
      l_qr_config        tp_qr_config;


      function get_formatinfo(
          p_eclevel in pls_integer,
          p_mask    in pls_integer )
          return pls_integer
      is
          type tp_format is table of tp_config;
          l_format tp_format;
      begin
          l_format := tp_format( tp_config( 30660, 29427, 32170, 30877, 26159, 25368, 27713, 26998 ),
                                  tp_config( 21522, 20773, 24188, 23371, 17913, 16590, 20375, 19104 ),
                                  tp_config( 13663, 12392, 16177, 14854, 9396, 8579, 11994, 11245 ),
                                  tp_config( 5769, 5054, 7399, 6608, 1890, 597, 3340, 2107 ));
          return l_format( p_eclevel )( p_mask + 1 );
      end get_formatinfo;


      procedure add_patterns(
          p_version in pls_integer,
          p_matrix  in out nocopy tp_matrix )
      is
          l_width        pls_integer := 4 * p_version + 17;
          type tp_inf    is table of pls_integer;
          type tp_pos    is table of pls_integer;
          type tp_align  is table of tp_pos;
          l_align        tp_align;
          l_info         tp_inf;
          l_version_info pls_integer;
          l_cnt          pls_integer;
          l_bit          pls_integer;


          procedure add_finder(
              p_x in pls_integer,
              p_y in pls_integer,
              p_w in pls_integer )
          is
              l_sx pls_integer := case p_w when 2 then l_width -  8 else 7 end;
              l_sy pls_integer := case p_w when 3 then l_width -  8 else 7 end;
              l_dx pls_integer := case p_w when 2 then 1 else -1 end;
              l_dy pls_integer := case p_w when 3 then 1 else -1 end;
          begin
              for i in -3 .. 3
              loop
                  for j in -3 .. 3
                  loop
                      p_matrix( p_x + i )( p_y + j ) := 1;
                  end loop;
              end loop;

              for i in -2 .. 2
              loop
                  p_matrix( p_x + i )( p_y - 2 ) := 0;
                  p_matrix( p_x + i )( p_y + 2 ) := 0;
                  p_matrix( p_x - 2 )( p_y + i ) := 0;
                  p_matrix( p_x + 2 )( p_y - i ) := 0;
              end loop;
              for i in 0 .. 7
              loop
                  p_matrix( p_x + ( i - 4 ) * l_dx )( p_y - 4 * l_dy ) := 0;
                  if p_w != 3 then  
                      p_matrix( p_x + ( i - 4 ) * l_dx )( p_y + 5 ) := 1;
                  end if;
                  p_matrix( p_x - 4 * l_dx )( p_y + ( i - 4 ) * l_dy ) := 0;
                  if p_w != 2 then  
                      p_matrix( p_x + 5 )( p_y + ( i - 4 ) * l_dy ) := 1;
                  end if;
              end loop;
          end add_finder;


          procedure add_aligment(
              p_x in pls_integer,
              p_y in pls_integer )
          is
          begin
              for i in -2 .. 2
              loop
                  for j in -2 .. 2
                  loop
                      p_matrix( p_x + i )( p_y + j ) := 1;
                  end loop;
              end loop;
              for i in -1 .. 1
              loop
                  p_matrix( p_x + i )( p_y - 1 ) := 0;
                  p_matrix( p_x + i )( p_y + 1 ) := 0;
              end loop;
              p_matrix( p_x + 1 )( p_y ) := 0;
              p_matrix( p_x - 1 )( p_y ) := 0;
          end add_aligment;
      begin
          for r in 0 .. l_width - 1
          loop
              for c in 0 .. l_width - 1
              loop
                  p_matrix( r )( c ) := 3; 
              end loop;
          end loop;

          add_finder( 3, 3, 1 );
          add_finder( l_width - 4, 3, 2 );
          add_finder( 3, l_width - 4, 3 );
          p_matrix( 8 )( 8 ) := 1; 

          for i in 8 .. l_width - 9
          loop
              p_matrix( i )( 6 ) := 1 - mod( i, 2 ); 
              p_matrix( 6 )( i ) := 1 - mod( i, 2 ); 
          end loop;

          if p_version > 1 then
              add_aligment( l_width - 7, l_width - 7 );
              if p_version > 6 then
                  l_align := tp_align(
                              tp_pos( 6, 22, 38 ), 
                              tp_pos( 6, 24, 42 ), 
                              tp_pos( 6, 26, 46 ), 
                              tp_pos( 6, 28, 50 ), 
                              tp_pos( 6, 30, 54 ), 
                              tp_pos( 6, 32, 58 ), 
                              tp_pos( 6, 34, 62 ), 
                              tp_pos( 6, 26, 46, 66 ), 
                              tp_pos( 6, 26, 48, 70 ), 
                              tp_pos( 6, 26, 50, 74 ), 
                              tp_pos( 6, 30, 54, 78 ), 
                              tp_pos( 6, 30, 56, 82 ), 
                              tp_pos( 6, 30, 58, 86 ), 
                              tp_pos( 6, 34, 62, 90 ), 
                              tp_pos( 6, 28, 50, 72,  94 ), 
                              tp_pos( 6, 26, 50, 74,  98 ), 
                              tp_pos( 6, 30, 54, 78, 102 ), 
                              tp_pos( 6, 28, 54, 80, 106 ), 
                              tp_pos( 6, 32, 58, 84, 110 ), 
                              tp_pos( 6, 30, 58, 86, 114 ), 
                              tp_pos( 6, 34, 62, 90, 118 ), 
                              tp_pos( 6, 26, 50, 74,  98, 122 ), 
                              tp_pos( 6, 30, 54, 78, 102, 126 ), 
                              tp_pos( 6, 26, 52, 78, 104, 130 ), 
                              tp_pos( 6, 30, 56, 82, 108, 134 ), 
                              tp_pos( 6, 34, 60, 86, 112, 138 ), 
                              tp_pos( 6, 30, 58, 86, 114, 142 ), 
                              tp_pos( 6, 34, 62, 90, 118, 146 ), 
                              tp_pos( 6, 30, 54, 78, 102, 126, 150 ), 
                              tp_pos( 6, 24, 50, 76, 102, 128, 154 ), 
                              tp_pos( 6, 28, 54, 80, 106, 132, 158 ), 
                              tp_pos( 6, 32, 58, 84, 110, 136, 162 ), 
                              tp_pos( 6, 26, 54, 82, 110, 138, 166 ), 
                              tp_pos( 6, 30, 58, 86, 114, 142, 170 )); 
                  l_cnt   := l_align( l_version - 6 ).count;
                  for i in 1 .. l_cnt
                  loop
                      for j in 1 .. l_cnt
                      loop
                          if i between 2 and l_cnt - 1 or j between 2 and l_cnt - 1 then
                              add_aligment(
                                  l_align( l_version - 6 )( i ),
                                  l_align( l_version - 6 )( j ));
                          end if;
                      end loop;
                  end loop;

                  l_info  := tp_inf(
                      31892, 34236, 39577, 42195, 48118, 51042, 55367, 58893, 63784,
                      68472, 70749, 76311, 79154, 84390, 87683, 92361, 96236, 102084,
                      102881, 110507, 110734, 117786, 119615, 126325, 127568, 133589,
                      136944, 141498, 145311, 150283, 152622, 158308, 161089, 167017 );
                  l_version_info := l_info( l_version - 6 );
                  for i in 0 .. 5
                  loop
                      for j in 0 .. 2
                      loop
                          l_bit := sign( bitand( l_version_info, power( 2, i * 3 + j ) ) );
                          p_matrix( l_width - 11 + j )( i ) := l_bit; 
                          p_matrix( i )( l_width - 11 + j ) := l_bit; 
                      end loop;
                  end loop;
              end if;
          end if;
      end add_patterns;


      procedure add_stream(
          p_width  in pls_integer,
          p_stream in tp_bits,
          p_matrix in out nocopy tp_matrix )
      is
          l_x         pls_integer;
          l_y         pls_integer;
          l_direction pls_integer := -1;


          procedure next_pos
          is
          begin
              if l_x is null then
                  l_x := p_width - 1;
                  l_y := p_width - 1;
              else
                  if ( l_x > 5 and mod( l_x, 2 ) = 0
                      or l_x < 6 and mod( l_x, 2 ) = 1 ) then
                      l_x := l_x - 1;
                  else
                      l_x := l_x + 1;
                      l_y := l_y + l_direction;
                  end if;
                  if l_y < 0 then
                      l_x         := l_x - case when l_x = 8 then 3 else 2 end; 
                      l_y         := 0;
                      l_direction := 1;
                  elsif l_y >= p_width then
                      l_x         := l_x - 2;
                      l_y         := p_width - 1;
                      l_direction := - 1;
                  end if;
                  if l_y = 6 or l_x = 6 or p_matrix( l_x )( l_y ) != 3 then
                      next_pos;
                  end if;
              end if;
          end next_pos;
      begin
          for i in 0 .. p_stream.count - 1
          loop
              next_pos;
              p_matrix( l_x )( l_y ) := 128 + p_stream( i );
          end loop;

          for i in 0 .. 1
          loop
              for j in 9 .. p_width - 8
              loop
                  if p_matrix( i )( j ) between 2 and 127 then
                      p_matrix( i )( j ) := 128;
                  end if;
              end loop;
          end loop;
      end add_stream;


      function get_qr_config
          return tp_qr_config
      is
      begin
          return tp_qr_config(
                  tp_ecc_config(
                      tp_config( 19,7,41,25,17,16,1,1,19 ), 
                      tp_config( 16,10,34,20,14,13,1,1,16 ),
                      tp_config( 13,13,27,16,11,10,1,1,13 ),
                      tp_config( 9,17,17,10,7,6,1,1,9 )),
                  tp_ecc_config(
                      tp_config( 34,10,77,47,32,31,1,1,34 ), 
                      tp_config( 28,16,63,38,26,25,1,1,28 ),
                      tp_config( 22,22,48,29,20,19,1,1,22 ),
                      tp_config( 16,28,34,20,14,13,1,1,16 )),
                  tp_ecc_config(
                      tp_config( 55,15,127,77,53,52,1,1,55 ), 
                      tp_config( 44,26,101,61,42,41,1,1,44 ),
                      tp_config( 34,36,77,47,32,31,1,2,17 ),
                      tp_config( 26,44,58,35,24,23,1,2,13 )),
                  tp_ecc_config(
                      tp_config( 80,20,187,114,78,77,1,1,80 ), 
                      tp_config( 64,36,149,90,62,61,1,2,32 ),
                      tp_config( 48,52,111,67,46,45,1,2,24 ),
                      tp_config( 36,64,82,50,34,33,1,4,9 )),
                  tp_ecc_config(
                      tp_config( 108,26,255,154,106,105,1,1,108 ), 
                      tp_config( 86,48,202,122,84,83,1,2,43 ),
                      tp_config( 62,72,144,87,60,59,2,2,15,2,16 ),
                      tp_config( 46,88,106,64,44,43,2,2,11,2,12 )),
                  tp_ecc_config(
                      tp_config( 136,36,322,195,134,133,1,2,68 ), 
                      tp_config( 108,64,255,154,106,105,1,4,27 ),
                      tp_config( 76,96,178,108,74,73,1,4,19 ),
                      tp_config( 60,112,139,84,58,57,1,4,15 )),
                  tp_ecc_config(
                      tp_config( 156,40,370,224,154,153,1,2,78 ), 
                      tp_config( 124,72,293,178,122,121,1,4,31 ),
                      tp_config( 88,108,207,125,86,85,2,2,14,4,15 ),
                      tp_config( 66,130,154,93,64,63,2,4,13,1,14 )),
                  tp_ecc_config(
                      tp_config( 194,48,461,279,192,191,1,2,97 ), 
                      tp_config( 154,88,365,221,152,151,2,2,38,2,39 ),
                      tp_config( 110,132,259,157,108,107,2,4,18,2,19 ),
                      tp_config( 86,156,202,122,84,83,2,4,14,2,15 )),
                  tp_ecc_config(
                      tp_config( 232,60,552,335,230,229,1,2,116 ), 
                      tp_config( 182,110,432,262,180,179,2,3,36,2,37 ),
                      tp_config( 132,160,312,189,130,129,2,4,16,4,17 ),
                      tp_config( 100,192,235,143,98,97,2,4,12,4,13 )),
                  tp_ecc_config(
                      tp_config( 274,72,652,395,271,270,2,2,68,2,69 ), 
                      tp_config( 216,130,513,311,213,212,2,4,43,1,44 ),
                      tp_config( 154,192,364,221,151,150,2,6,19,2,20 ),
                      tp_config( 122,224,288,174,119,118,2,6,15,2,16 )),
                  tp_ecc_config(
                      tp_config( 324,80,772,468,321,320,1,4,81 ), 
                      tp_config( 254,150,604,366,251,250,2,1,50,4,51 ),
                      tp_config( 180,224,427,259,177,176,2,4,22,4,23 ),
                      tp_config( 140,264,331,200,137,136,2,3,12,8,13 )),
                  tp_ecc_config(
                      tp_config( 370,96,883,535,367,366,2,2,92,2,93 ), 
                      tp_config( 290,176,691,419,287,286,2,6,36,2,37 ),
                      tp_config( 206,260,489,296,203,202,2,4,20,6,21 ),
                      tp_config( 158,308,374,227,155,154,2,7,14,4,15 )),
                  tp_ecc_config(
                      tp_config( 428,104,1022,619,425,424,1,4,107 ), 
                      tp_config( 334,198,796,483,331,330,2,8,37,1,38 ),
                      tp_config( 244,288,580,352,241,240,2,8,20,4,21 ),
                      tp_config( 180,352,427,259,177,176,2,12,11,4,12 )),
                  tp_ecc_config(
                      tp_config( 461,120,1101,667,458,457,2,3,115,1,116 ), 
                      tp_config( 365,216,871,528,362,361,2,4,40,5,41 ),
                      tp_config( 261,320,621,376,258,257,2,11,16,5,17 ),
                      tp_config( 197,384,468,283,194,193,2,11,12,5,13 )),
                  tp_ecc_config(
                      tp_config( 523,132,1250,758,520,519,2,5,87,1,88 ), 
                      tp_config( 415,240,991,600,412,411,2,5,41,5,42 ),
                      tp_config( 295,360,703,426,292,291,2,5,24,7,25 ),
                      tp_config( 223,432,530,321,220,219,2,11,12,7,13 )),
                  tp_ecc_config(
                      tp_config( 589,144,1408,854,586,585,2,5,98,1,99 ), 
                      tp_config( 453,280,1082,656,450,449,2,7,45,3,46 ),
                      tp_config( 325,408,775,470,322,321,2,15,19,2,20 ),
                      tp_config( 253,480,602,365,250,249,2,3,15,13,16 )),
                  tp_ecc_config(
                      tp_config( 647,168,1548,938,644,643,2,1,107,5,108 ), 
                      tp_config( 507,308,1212,734,504,503,2,10,46,1,47 ),
                      tp_config( 367,448,876,531,364,363,2,1,22,15,23 ),
                      tp_config( 283,532,674,408,280,279,2,2,14,17,15 )),
                  tp_ecc_config(
                      tp_config( 721,180,1725,1046,718,717,2,5,120,1,121 ), 
                      tp_config( 563,338,1346,816,560,559,2,9,43,4,44 ),
                      tp_config( 397,504,948,574,394,393,2,17,22,1,23 ),
                      tp_config( 313,588,746,452,310,309,2,2,14,19,15 )),
                  tp_ecc_config(
                      tp_config( 795,196,1903,1153,792,791,2,3,113,4,114 ), 
                      tp_config( 627,364,1500,909,624,623,2,3,44,11,45 ),
                      tp_config( 445,546,1063,644,442,441,2,17,21,4,22 ),
                      tp_config( 341,650,813,493,338,337,2,9,13,16,14 )),
                  tp_ecc_config(
                      tp_config( 861,224,2061,1249,858,857,2,3,107,5,108 ), 
                      tp_config( 669,416,1600,970,666,665,2,3,41,13,42 ),
                      tp_config( 485,600,1159,702,482,481,2,15,24,5,25 ),
                      tp_config( 385,700,919,557,382,381,2,15,15,10,16 )),
                  tp_ecc_config(
                      tp_config( 932,224,2232,1352,929,928,2,4,116,4,117 ), 
                      tp_config( 714,442,1708,1035,711,710,1,17,42 ),
                      tp_config( 512,644,1224,742,509,508,2,17,22,6,23 ),
                      tp_config( 406,750,969,587,403,402,2,19,16,6,17 )),
                  tp_ecc_config(
                      tp_config( 1006,252,2409,1460,1003,1002,2,2,111,7,112 ), 
                      tp_config( 782,476,1872,1134,779,778,1,17,46 ),
                      tp_config( 568,690,1358,823,565,564,2,7,24,16,25 ),
                      tp_config( 442,816,1056,640,439,438,1,34,13 )),
                  tp_ecc_config(
                      tp_config( 1094,270,2620,1588,1091,1090,2,4,121,5,122 ), 
                      tp_config( 860,504,2059,1248,857,856,2,4,47,14,48 ),
                      tp_config( 614,750,1468,890,611,610,2,11,24,14,25 ),
                      tp_config( 464,900,1108,672,461,460,2,16,15,14,16 )),
                  tp_ecc_config(
                      tp_config( 1174,300,2812,1704,1171,1170,2,6,117,4,118 ), 
                      tp_config( 914,560,2188,1326,911,910,2,6,45,14,46 ),
                      tp_config( 664,810,1588,963,661,660,2,11,24,16,25 ),
                      tp_config( 514,960,1228,744,511,510,2,30,16,2,17 )),
                  tp_ecc_config(
                      tp_config( 1276,312,3057,1853,1273,1272,2,8,106,4,107 ), 
                      tp_config( 1000,588,2395,1451,997,996,2,8,47,13,48 ),
                      tp_config( 718,870,1718,1041,715,714,2,7,24,22,25 ),
                      tp_config( 538,1050,1286,779,535,534,2,22,15,13,16 )),
                  tp_ecc_config(
                      tp_config( 1370,336,3283,1990,1367,1366,2,10,114,2,115 ), 
                      tp_config( 1062,644,2544,1542,1059,1058,2,19,46,4,47 ),
                      tp_config( 754,952,1804,1094,751,750,2,28,22,6,23 ),
                      tp_config( 596,1110,1425,864,593,592,2,33,16,4,17 )),
                  tp_ecc_config(
                      tp_config( 1468,360,3517,2132,1465,1464,2,8,122,4,123 ), 
                      tp_config( 1128,700,2701,1637,1125,1124,2,22,45,3,46 ),
                      tp_config( 808,1020,1933,1172,805,804,2,8,23,26,24 ),
                      tp_config( 628,1200,1501,910,625,624,2,12,15,28,16 )),
                  tp_ecc_config(
                      tp_config( 1531,390,3669,2223,1528,1527,2,3,117,10,118 ), 
                      tp_config( 1193,728,2857,1732,1190,1189,2,3,45,23,46 ),
                      tp_config( 871,1050,2085,1263,868,867,2,4,24,31,25 ),
                      tp_config( 661,1260,1581,958,658,657,2,11,15,31,16 )),
                  tp_ecc_config(
                      tp_config( 1631,420,3909,2369,1628,1627,2,7,116,7,117 ), 
                      tp_config( 1267,784,3035,1839,1264,1263,2,21,45,7,46 ),
                      tp_config( 911,1140,2181,1322,908,907,2,1,23,37,24 ),
                      tp_config( 701,1350,1677,1016,698,697,2,19,15,26,16 )),
                  tp_ecc_config(
                      tp_config( 1735,450,4158,2520,1732,1731,2,5,115,10,116 ), 
                      tp_config( 1373,812,3289,1994,1370,1369,2,19,47,10,48 ),
                      tp_config( 985,1200,2358,1429,982,981,2,15,24,25,25 ),
                      tp_config( 745,1440,1782,1080,742,741,2,23,15,25,16 )),
                  tp_ecc_config(
                      tp_config( 1843,480,4417,2677,1840,1839,2,13,115,3,116 ), 
                      tp_config( 1455,868,3486,2113,1452,1451,2,2,46,29,47 ),
                      tp_config( 1033,1290,2473,1499,1030,1029,2,42,24,1,25 ),
                      tp_config( 793,1530,1897,1150,790,789,2,23,15,28,16 )),
                  tp_ecc_config(
                      tp_config( 1955,510,4686,2840,1952,1951,1,17,115 ), 
                      tp_config( 1541,924,3693,2238,1538,1537,2,10,46,23,47 ),
                      tp_config( 1115,1350,2670,1618,1112,1111,2,10,24,35,25 ),
                      tp_config( 845,1620,2022,1226,842,841,2,19,15,35,16 )),
                  tp_ecc_config(
                      tp_config( 2071,540,4965,3009,2068,2067,2,17,115,1,116 ), 
                      tp_config( 1631,980,3909,2369,1628,1627,2,14,46,21,47 ),
                      tp_config( 1171,1440,2805,1700,1168,1167,2,29,24,19,25 ),
                      tp_config( 901,1710,2157,1307,898,897,2,11,15,46,16 )),
                  tp_ecc_config(
                      tp_config( 2191,570,5253,3183,2188,2187,2,13,115,6,116 ), 
                      tp_config( 1725,1036,4134,2506,1722,1721,2,14,46,23,47 ),
                      tp_config( 1231,1530,2949,1787,1228,1227,2,44,24,7,25 ),
                      tp_config( 961,1800,2301,1394,958,957,2,59,16,1,17 )),
                  tp_ecc_config(
                      tp_config( 2306,570,5529,3351,2303,2302,2,12,121,7,122 ), 
                      tp_config( 1812,1064,4343,2632,1809,1808,2,12,47,26,48 ),
                      tp_config( 1286,1590,3081,1867,1283,1282,2,39,24,14,25 ),
                      tp_config( 986,1890,2361,1431,983,982,2,22,15,41,16 )),
                  tp_ecc_config(
                      tp_config( 2434,600,5836,3537,2431,2430,2,6,121,14,122 ), 
                      tp_config( 1914,1120,4588,2780,1911,1910,2,6,47,34,48 ),
                      tp_config( 1354,1680,3244,1966,1351,1350,2,46,24,10,25 ),
                      tp_config( 1054,1980,2524,1530,1051,1050,2,2,15,64,16 )),
                  tp_ecc_config(
                      tp_config( 2566,630,6153,3729,2563,2562,2,17,122,4,123 ), 
                      tp_config( 1992,1204,4775,2894,1989,1988,2,29,46,14,47 ),
                      tp_config( 1426,1770,3417,2071,1423,1422,2,49,24,10,25 ),
                      tp_config( 1096,2100,2625,1591,1093,1092,2,24,15,46,16 )),
                  tp_ecc_config(
                      tp_config( 2702,660,6479,3927,2699,2698,2,4,122,18,123 ), 
                      tp_config( 2102,1260,5039,3054,2099,2098,2,13,46,32,47 ),
                      tp_config( 1502,1860,3599,2181,1499,1498,2,48,24,14,25 ),
                      tp_config( 1142,2220,2735,1658,1139,1138,2,42,15,32,16 )),
                  tp_ecc_config(
                      tp_config( 2812,720,6743,4087,2809,2808,2,20,117,4,118 ), 
                      tp_config( 2216,1316,5313,3220,2213,2212,2,40,47,7,48 ),
                      tp_config( 1582,1950,3791,2298,1579,1578,2,43,24,22,25 ),
                      tp_config( 1222,2310,2927,1774,1219,1218,2,10,15,67,16 )),
                  tp_ecc_config(
                      tp_config( 2956,750,7089,4296,2953,2952,2,19,118,6,119 ), 
                      tp_config( 2334,1372,5596,3391,2331,2330,2,18,47,31,48 ),
                      tp_config( 1666,2040,3993,2420,1663,1662,2,34,24,34,25 ),
                      tp_config( 1276,2430,3057,1852,1273,1272,2,20,15,61,16 )));
      end get_qr_config;


      function get_version(
          p_len     in pls_integer,
          p_eclevel in pls_integer,
          p_mode    in pls_integer )
          return pls_integer
      is
          l_version pls_integer;
          l_tmp     pls_integer;
      begin
          l_version := 1;
          while p_len > l_qr_config( l_version )( p_eclevel )( p_mode )
          loop
              l_version := l_version + 1;
          end loop;
          return l_version;
      end get_version;


      procedure add_byte_data(
          p_val     in raw,
          p_version in pls_integer,
          p_stream  in out nocopy tp_bits )
      is
          l_len pls_integer := sys.utl_raw.length( p_val );
      begin
          append_bits( p_stream, 4, 4 );  
          append_bits( p_stream, l_len, case when p_version <= 9 then 8 else 16 end );
          for i in 1 .. l_len
          loop
              append_bits( p_stream, to_number( sys.utl_raw.substr( p_val, i, 1 ), 'xx' ), 8 );
          end loop;
      end add_byte_data;

  begin
      l_eclevel   := case upper( p_params.eclevel )
                          when 'L' then 1
                          when 'M' then 2
                          when 'Q' then 3
                          when 'H' then 4
                          else 2 end;
      l_qr_config := get_qr_config;

      if translate( p_val, '#0123456789', '#' ) is null then  
          l_version := get_version( length( p_val ), l_eclevel, 3 );
          append_bits( l_stream, 1, 4 ); 
          append_bits(
              l_stream,
              length( p_val ),
              case
                  when l_version <= 9 then 10
                  when l_version <= 26 then 12
                  else 14 end );
          for i in 1 .. trunc( length( p_val ) / 3 )
          loop
              append_bits( l_stream, substr( p_val, i * 3 - 2, 3 ), 10 );
          end loop;
          case mod( length( p_val ), 3 )
              when 1 then append_bits( l_stream, substr( p_val, -1 ), 4 );
              when 2 then append_bits( l_stream, substr( p_val, -2 ), 7 );
              else null;
          end case;
      elsif translate( p_val, '#0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:', '#' ) is null then 
          l_version := get_version( length( p_val ), l_eclevel, 4 );
          append_bits( l_stream, 2, 4 ); 
          append_bits(
              l_stream,
              length( p_val ),
              case
                  when l_version <= 9 then 9
                  when l_version <= 26 then 11
                  else 13 end );
          l_tmp := sys.utl_raw.translate(
                      sys.utl_raw.cast_to_raw( p_val ),
                      sys.utl_raw.concat(
                          sys.utl_raw.xrange( '30', '39' ),
                          sys.utl_raw.xrange( '41', '5A' ),
                          '2024252A2B2D2E2F3A' ),
                      sys.utl_raw.xrange( '00', '2C' ));
          for i in 1 .. trunc( length( p_val ) / 2 )
          loop
              append_bits(
                  l_stream,
                  to_number( sys.utl_raw.substr( l_tmp, i * 2 - 1, 1 ), 'xx' ) * 45
                     + to_number( sys.utl_raw.substr( l_tmp, i * 2, 1 ), 'xx' ),
                  11 );
          end loop;
          if mod( length( p_val ), 2 ) = 1 then
              append_bits( l_stream, to_number( sys.utl_raw.substr( l_tmp, -1 ), 'xx' ), 6 );
          end if;
      elsif (( isnchar( p_val )
                  and sys.utl_i18n.raw_to_nchar( sys.utl_i18n.string_to_raw( p_val, 'US7ASCII' ), 'US7ASCII' ) = p_val )
              or
              ( not isnchar( p_val )
                  and sys.utl_i18n.raw_to_char(
                          sys.utl_i18n.string_to_raw( p_val, 'US7ASCII' ),
                          'US7ASCII' ) = p_val )) then 
              l_version := get_version( length( p_val ), l_eclevel, 5 );
              l_tmp     := sys.utl_i18n.string_to_raw( p_val, 'US7ASCII' );
              add_byte_data( l_tmp, l_version, l_stream );
      else 
          append_bits( l_stream, 7, 4 );  
          append_bits( l_stream, 26, 8 ); 
          l_tmp     := sys.utl_i18n.string_to_raw( p_val, 'AL32UTF8' );
          l_version := get_version( sys.utl_raw.length( l_tmp ), l_eclevel, 6 );
          add_byte_data( l_tmp, l_version, l_stream );
      end if;


      l_sz := l_qr_config( l_version )( l_eclevel )( 1 ) * 8;
      for i in 1 .. 4
      loop
         if l_stream.count < l_sz then
             append_bits( l_stream, 0, 1 );
         end if;
     end loop;

     if mod( l_stream.count, 8 ) > 0 then
         append_bits( l_stream, 0, 8 - mod( l_stream.count, 8 ));
     end if;

     l_len := l_stream.count;
     loop
         exit when l_len >= l_sz;
         append_bits( l_stream, 236, 8 );
         l_len := l_len + 8;
         exit when l_len >= l_sz;
         append_bits( l_stream, 17, 8 );
         l_len := l_len + 8;
     end loop;


     declare
         l_data      tp_bits;
         l_ecc       tp_bits;
         l_blocks    pls_integer;
         l_block_idx pls_integer;
         l_ec_bytes  pls_integer;
         l_dw_bytes  pls_integer;
         l_offs      pls_integer;
         l_noffs     pls_integer;
         l_eoffs     pls_integer;
         l_block     tp_bits;
         l_new       tp_bits;
     begin
         l_blocks := l_qr_config( l_version)( l_eclevel )( 8 );
         if l_qr_config( l_version)( l_eclevel )( 7 ) > 1 then
             l_blocks := l_blocks + l_qr_config( l_version)( l_eclevel )( 10 );
         end if;
         l_ec_bytes  := l_qr_config( l_version)( l_eclevel )( 2 ) / l_blocks;
         l_data      := bitstoword( l_stream, 8 );
         l_offs      := 0;
         l_noffs     := 0;
         l_block_idx := 0;
         l_eoffs     := l_qr_config( l_version)( l_eclevel )( 1 );
         for i in 1 .. l_qr_config( l_version)( l_eclevel )( 7 )
         loop
             l_dw_bytes := l_qr_config( l_version)( l_eclevel )( 7 + i * 2 );
             for j in 1 .. l_qr_config( l_version)( l_eclevel )( 6 + i * 2 )
             loop
                 l_noffs := l_block_idx;
                 for x in 0 .. l_dw_bytes - 1
                 loop
                     l_block( x ) := l_data( x + l_offs );
                     l_new( l_noffs ) := l_block( x );
                     if i > 1 and x >= l_qr_config( l_version)( l_eclevel )( 9 ) - 1 then
                         l_noffs := l_noffs + l_qr_config( l_version)( l_eclevel )( 10 );
                     else
                         l_noffs := l_noffs + l_blocks;
                     end if;
                 end loop;
                 l_offs := l_offs + l_dw_bytes;
                 l_ecc  := reed_solomon( l_block, 285, 256, l_ec_bytes, 0 );
                 for x in 0 .. l_ec_bytes - 1
                 loop
                     l_new( l_eoffs + l_block_idx + x * l_blocks ) := l_ecc( x );
                 end loop;
                 l_block.delete;
                 l_ecc.delete;
                 l_block_idx := l_block_idx + 1;
             end loop;
         end loop;
         l_stream.delete;
         for i in l_new.first .. l_new.last
         loop
             append_bits( l_stream, l_new( i ), 8 );
         end loop;
     end;

     add_patterns( l_version, p_matrix );
     add_stream( 4 * l_version + 17, l_stream, p_matrix );

     l_stream.delete;

     declare
         l_width   pls_integer := 4 * l_version + 17;
         l_mask    pls_integer;
         l_hbit    pls_integer;
         l_hcnt    pls_integer;
         l_vbit    pls_integer;
         l_vcnt    pls_integer;
         l_masked  tp_matrix;
         l_n1      pls_integer;
         l_n2      pls_integer;
         l_n3      pls_integer;
         l_n4      pls_integer;
         l_best    number;
         l_score   number;


         function mask_function(
             f in pls_integer,
             i in pls_integer,
             j in pls_integer )
             return pls_integer
         is
         begin
             return nvl(
                 case
                     when f = 0 and mod( i+j, 2 ) = 0 then 1
                     when f = 1 and mod( i, 2 ) = 0 then 1
                     when f = 2 and mod( j, 3 ) = 0 then 1
                     when f = 3 and mod( i+j, 3 ) = 0 then 1
                     when f = 4 and mod(trunc(i/2)+trunc(j/3),2) = 0 then 1
                     when f = 5 and mod(i*j,2) + mod(i*j,3) = 0 then 1
                     when f = 6 and mod(mod(i*j,2) + mod(i*j,3), 2 ) = 0 then 1
                     when f = 7 and mod(mod(i*j,3) + mod(i+j,2), 2 ) = 0 then 1
                 end,
                 0 );
         end mask_function;


         procedure mask_matrix(
             p_mat    in tp_matrix,
             p_masked in out nocopy tp_matrix,
             p_mask   in pls_integer )
         is
             l_t_info   pls_integer;
         begin
             for y in 0 .. l_width - 1
             loop
                 for x in 0 .. l_width - 1
                 loop
                     if p_mat( y )( x ) > 127 then
                         p_masked( y )( x ) := bitxor( p_mat( y )( x ) - 128, mask_function( p_mask, x, y ));
                     else
                         p_masked( y )( x ) := p_mat( y )( x );
                     end if;
                 end loop;
             end loop;
             l_t_info := get_formatinfo( l_eclevel, p_mask );
             for i in 0 .. 5
             loop
                 p_masked(i)(8) := sign( bitand( l_t_info, power( 2, 14 - i )));
                 p_masked(8)(i) := sign( bitand( l_t_info, power( 2, i )));
             end loop;
             p_masked(7)(8) := sign( bitand( l_t_info, power( 2, 8 )));
             p_masked(8)(8) := sign( bitand( l_t_info, power( 2, 7 )));
             p_masked(8)(7) := sign( bitand( l_t_info, power( 2, 6 )));
             for i in 0 .. 6
             loop
                 p_masked(8)(l_width-1-i) := sign( bitand( l_t_info, power( 2, 14 - i )));
                 p_masked(l_width-1-i)(8) := sign( bitand( l_t_info, power( 2, i )));
             end loop;
             p_masked(l_width - 8)(8) := sign( bitand( l_t_info, power( 2, 7 ) ) );
         end mask_matrix;


         procedure score_rule1(
             p_cnt in pls_integer )
         is
         begin
             if p_cnt >= 5 then
                 l_n1 := l_n1 + 3 + p_cnt - 5;
             end if;
         end score_rule1;


         procedure rule1(
             p_bit  in pls_integer,
             p_prev in out pls_integer,
             p_cnt  in out pls_integer )
         is
         begin
             if p_bit = p_prev then
                 p_cnt := p_cnt + 1;
             else
                 score_rule1( p_cnt );
                 p_prev := p_bit;
                 p_cnt  := 1;
             end if;
         end rule1;


         procedure rule3(
             p_x  in pls_integer,
             p_y  in pls_integer,
             p_xy in boolean )
         is
             function gfm( p in pls_integer )
                 return pls_integer
             is
             begin
                 return sign(
                     case
                         when p_xy then
                             l_masked( p_y )( p_x + p )
                         else
                             l_masked( p_y + p )( p_x )
                     end );
             end;
         begin
             if (
                 case
                     when p_xy then p_x
                     else p_y end >= 6
                 and gfm( - 6 ) = 1
                 and gfm( - 5 ) = 0
                 and gfm( - 4 ) = 1
                 and gfm( - 3 ) = 1
                 and gfm( - 2 ) = 1
                 and gfm( - 1 ) = 0
                 and gfm( 0 ) = 1
                 and ((
                     case
                         when p_xy then p_x
                         else p_y end >= 10
                     and gfm( - 7 ) + gfm( - 8 ) + gfm( - 9 ) + gfm( - 10 ) = 0 )
                     or (
                         case
                             when p_xy then p_x
                             else p_y end <= l_width - 5
                         and gfm( 1 ) + gfm( 2 ) + gfm( 3 ) + gfm( 4 ) = 0 )
                 )) then
                     l_n3 := l_n3 + 1;
             end if;
         end rule3;

     begin
         l_best := 99999999;
         for m in 0 .. 7
         loop
             mask_matrix( p_matrix, l_masked, m );
             l_n1 := 0;
             l_n2 := 0;
             l_n3 := 0;
             l_n4 := 0;
             for y in 0 .. l_width - 1
             loop
                 l_hbit := -1;
                 l_hcnt := 0;
                 l_vbit := -1;
                 l_vcnt := 0;
                 for x in 0 .. l_width - 1
                 loop
                     rule1( sign( l_masked(y)(x) ), l_hbit, l_hcnt );
                     rule1( sign( l_masked(x)(y) ), l_vbit, l_vcnt );

                     if ( x > 0
                         and y > 0
                         and ( sign( l_masked(y)(x) ) + sign( l_masked(y)(x-1) )
                             + sign( l_masked(y-1)(x) ) + sign( l_masked(y-1)(x-1) )
                             ) in ( 0, 4 )) then
                         l_n2 := l_n2 + 1;
                     end if;

                     rule3( x, y, true );
                     rule3( x, y, false );

                     l_n4 := l_n4 + sign( l_masked(y)(x) );
                 end loop;
                 score_rule1( l_hcnt );
                 score_rule1( l_vcnt );
             end loop;

             l_n4    := trunc( 10 * abs( l_n4 * 2 - l_width * l_width ) / ( l_width * l_width ) );
             l_score := l_n1 + l_n2 * 3 + l_n3 * 40 + l_n4 * 10;
             if l_score < l_best then
                 l_mask := m;
                 l_best := l_score;
             end if;
         end loop;
         mask_matrix( p_matrix, p_matrix, l_mask );
     end;

     add_quiet( p_matrix, p_params, 4 );

 end gen_qrcode_matrix;

 function png_matrix(
     p_matrix in out nocopy tp_matrix,
     p_params in t_parameters )
     return raw
 is
     l_dat   blob;
     l_line  raw(32767);
     l_tmp   varchar2(32767);
     l_hsz   pls_integer;
     l_vsz   pls_integer;
     l_scale pls_integer;
 begin

     l_scale := p_params.png_scale;

     sys.dbms_lob.createtemporary( l_dat, true, sys.dbms_lob.call );
     l_hsz   := p_matrix.count;
     l_vsz   := p_matrix(1).count;
     for r in 0 .. l_vsz - 1
     loop
         l_tmp := '00';
         l_line := null;
         for c in 0 .. l_hsz - 1
         loop
             l_tmp := l_tmp ||
                     case
                         when p_matrix( c )( r ) > 0 then
                             rpad( '00', l_scale * 2, '00' )
                         else
                             rpad( '01', l_scale * 2, '01' ) end;
         end loop;
         for j in 1 .. l_scale
         loop
             l_line := sys.utl_raw.concat( l_line, l_tmp );
         end loop;
         sys.dbms_lob.writeappend( l_dat, sys.utl_raw.length( l_line ), l_line );
     end loop;
     p_matrix.delete;
     return generate_png( l_dat, l_hsz * l_scale, l_vsz * l_scale, p_params );
 end png_matrix;


 function qrcode(
     p_val    in varchar2 character set any_cs,
     p_params in t_parameters )
     return raw
 is
     l_matrix tp_matrix;
 begin
     gen_qrcode_matrix( p_val, p_params, l_matrix );
     return png_matrix( l_matrix, p_params );
 end qrcode;


 function barcode(
     p_val    in varchar2 character set any_cs,
     p_type   in varchar2,
     p_params in t_parameters )
     return raw
 is
 begin
     if p_val is not null then
         if upper( p_type ) like 'QR%' then
             return qrcode( p_val, p_params );         
         end if;
     end if;
     exception
         when others then
             null;
 end barcode;


 function barcode_blob(
     p_val    in varchar2 character set any_cs,
     p_type   in varchar2,
     p_params in t_parameters,
     p_format in varchar2 default c_format_type_png )
     return blob
 is
 begin

         return barcode( p_val, p_type, p_params );

 end barcode_blob;

 function get_qrcode_png(
     p_value             in varchar2,
     p_scale             in number         default c_default_scale,
     p_quiet             in number         default c_default_quiet,
     p_eclevel           in t_eclevel_type default c_default_eclevel,
     p_foreground_color  in varchar2       default c_default_foreground_color,
     p_background_color  in varchar2       default null )
     return blob
 is
     l_params   t_parameters;
 begin
     return barcode_blob(
                 p_val    => p_value,
                 p_type   => c_barcode_type_qr,
                 p_params => l_params,
                 p_format => c_format_type_png );
 end get_qrcode_png;

 ----------------
 FUNCTION qr_base64(QR_TEXT IN VARCHAR2) RETURN VARCHAR2 IS
    l_base64_text varchar2(2000):='';
BEGIN

    l_base64_text:= UTL_RAW.CAST_TO_VARCHAR2(
         UTL_ENCODE.BASE64_ENCODE(
           DBMS_LOB.SUBSTR(
             hc_qr.get_qrcode_png(
               p_value            => QR_TEXT
             ),
             4000, 1
           )
         ));

    RETURN l_base64_text;
EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END qr_base64;

 end hc_qr;
