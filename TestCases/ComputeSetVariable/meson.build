funcs = ['foo', 'bar', 'baz']
foreach x : funcs
    set_variable('have_' + x, true)
endforeach
# ana:var: have_foo = bool
# ana:var: have_bar = bool
# ana:var: have_baz = bool

foreach x : funcs
    set_variable(x + 'have_', true)
endforeach
# ana:var: foohave_ = bool
# ana:var: barhave_ = bool
# ana:var: bazhave_ = bool

foreach x : ['1']
    set_variable('have_' + x, true)
endforeach
# ana:var: have_1 = bool

foreach x : ['2', '3']
    set_variable('have_@0@'.format(x), true)
endforeach
# ana:var: have_2 = bool
# ana:var: have_3 = bool

python_tools = [
    'glib-genmarshal',
    'glib-mkenums',
]
foreach tool : python_tools
    set_variable(tool.underscorify(), true)
endforeach
# ana:var: glib_genmarshal = bool
# ana:var: glib_mkenums = bool

tests = [
    'hb-shape-fuzzer.cc',
    'hb-subset-fuzzer.cc',
    'hb-set-fuzzer.cc',
    'hb-draw-fuzzer.cc',
]
if get_option('experimental_api')
    tests += 'hb-repacker-fuzzer.cc'
endif
foreach file_name : tests
    test_name = file_name.split('.')[0]
    set_variable('@0@_exe'.format(test_name.underscorify()), true)
endforeach
# ana:var: hb_shape_fuzzer_exe = bool
# ana:var: hb_subset_fuzzer_exe = bool
# ana:var: hb_set_fuzzer_exe = bool
# ana:var: hb_draw_fuzzer_exe = bool
# ana:var: hb_repacker_fuzzer_exe = bool

gdkpixbuf_bin = [
    ['gdk-pixbuf-csource'],
    ['gdk-pixbuf-pixdata'],
    ['gdk-pixbuf-query-loaders', ['queryloaders.c']],
]
foreach bin : gdkpixbuf_bin
    bin_name = bin[0]
    set_variable(bin_name.underscorify(), true)
endforeach
# ana:var: gdk_pixbuf_csource = bool
# ana:var: gdk_pixbuf_pixdata = bool
# ana:var: gdk_pixbuf_query_loaders = bool

vpx_features = [
    [
        'vpx/vp8cx.h',
        'vpx_codec_vp8_cx_algo',
        '-DHAVE_VP8_ENCODER',
        'VP8 encoder',
    ],
    [
        'vpx/vp8dx.h',
        'vpx_codec_vp8_dx_algo',
        '-DHAVE_VP8_DECODER',
        'VP8 decoder',
    ],
    [
        'vpx/vp8cx.h',
        'vpx_codec_vp9_cx_algo',
        '-DHAVE_VP9_ENCODER',
        'VP9 encoder',
    ],
    [
        'vpx/vp8dx.h',
        'vpx_codec_vp9_dx_algo',
        '-DHAVE_VP9_DECODER',
        'VP9 decoder',
    ],
]
foreach f : vpx_features
    set_variable('have_' + f.get(3).to_lower().underscorify(), true)
endforeach
# ana:var: have_vp8_encoder = bool
# ana:var: have_vp8_decoder = bool
# ana:var: have_vp9_encoder = bool
# ana:var: have_vp9_decoder = bool

vpx2_features = [
    [
        'vpx/vp6cx.h',
        'vpx_codec_vp6_cx_algo',
        '-DHAVE_VP6_ENCODER',
        'VP6 encoder',
    ],
    [
        'vpx/vp6dx.h',
        'vpx_codec_vp6_dx_algo',
        '-DHAVE_VP8_DECODER',
        'VP6 decoder',
    ],
    [
        'vpx/vp7cx.h',
        'vpx_codec_vp7_cx_algo',
        '-DHAVE_VP7_ENCODER',
        'VP7 encoder',
    ],
    [
        'vpx/vp7dx.h',
        'vpx_codec_vp7_dx_algo',
        '-DHAVE_VP7_DECODER',
        'VP7 decoder',
    ],
]
foreach f : vpx2_features
    set_variable('have_' + f[3].to_lower().underscorify(), true)
endforeach
# ana:var: have_vp6_encoder = bool
# ana:var: have_vp6_decoder = bool
# ana:var: have_vp7_encoder = bool
# ana:var: have_vp7_decoder = bool

test_apps = [
    [
        'srtp_driver',
        {
            'extra_sources': 'util.c',
            'run_args': '-v',
        },
    ],
    [
        'replay_driver',
        {
            'extra_sources': 'ut_sim.c',
            'run_args': '-v',
        },
    ],
    [
        'roc_driver',
        {
            'extra_sources': 'ut_sim.c',
            'run_args': '-v',
        },
    ],
    [
        'rdbx_driver',
        {
            'extra_sources': 'ut_sim.c',
            'run_args': '-v',
        },
    ],
    ['test_srtp', {'run_args': '-v'}],
    [
        'rtpw',
        {
            'extra_sources': ['rtp.c', 'util.c', '../crypto/math/datatypes.c'],
            'define_test': false,
        },
    ],
]
foreach t : test_apps
    test_name = t.get(0)
    set_variable(test_name + '_exe', true)
endforeach
# ana:var: rtpw_exe = bool

generated_headers = [
    {
        'scanner_args': ['server-header'],
        'output': 'wayland-server-protocol.h',
        'install': true,
    },
    {
        'scanner_args': ['server-header', '-c'],
        'output': 'wayland-server-protocol-core.h',
        'install': false,
    },
    {
        'scanner_args': ['client-header'],
        'output': 'wayland-client-protocol.h',
        'install': true,
    },
    {
        'scanner_args': ['client-header', '-c'],
        'output': 'wayland-client-protocol-core.h',
        'install': false,
    },
]
foreach gen : generated_headers
    output_file = gen.get('output')
    target_name = output_file.underscorify()
    set_variable(target_name, true)
endforeach
# ana:var: wayland_client_protocol_h = bool
# ana:var: wayland_server_protocol_h = bool
# ana:var: wayland_client_protocol_core_h = bool
# ana:var: wayland_server_protocol_core_h = bool

a1 = 'snake'
a2 = a1
a3 = a2
a4 = a3
set_variable('have_' + a4, true)
# ana:var: have_snake = bool

foreach target : ['header', 'source']
    ext = target == 'header' ? 'h' : 'c'
    set_variable('g_egldispatchstubs_' + ext, true)
endforeach
# ana:var: g_egldispatchstubs_c = bool
# ana:var: g_egldispatchstubs_h = bool

foreach g : ['gl', 'opengl', 'glesv1', 'glesv2']
    name = 'glapi_' + g
    set_variable('idep_' + name, true)
endforeach
# ana:var: idep_glapi_gl = bool
# ana:var: idep_glapi_opengl = bool
# ana:var: idep_glapi_glesv1 = bool
# ana:var: idep_glapi_glesv2 = bool

NAME1 = 0
plugins = [
    ['bookmarks', [gio_dep, libxml_dep, gom_dep], []],
    ['filesystem', [grilo_pls_dep], []],
    [
        'lua-factory',
        [lua_dep, libarchive_dep, grilo_net_dep, json_glib_dep, libxml_dep],
        [goa_dep, totem_plparser_mini_dep],
    ],
    [
        'youtube',
        [grilo_net_dep, libxml_dep, libgdata_dep, totem_plparser_dep],
        [],
    ],
]
foreach p : plugins
    varname = p[NAME1].underscorify()
    varname_enabled = varname + '_enabled'
    varname_idx = varname + '_idx'
    set_variable(varname_enabled, true)
    set_variable(varname_idx, true)
endforeach
# ana:var: bookmarks_enabled = bool
# ana:var: bookmarks_idx = bool
# ana:var: filesystem_enabled = bool
# ana:var: filesystem_idx = bool
# ana:var: lua_factory_enabled = bool
# ana:var: lua_factory_idx = bool
# ana:var: youtube_enabled = bool
# ana:var: youtube_idx = bool

foreach p : plugins
    name = p[NAME1].underscorify() + '_enabled'
    set_variable(name + 'foo', get_variable(name).to_string('yes', 'no'))
endforeach
# ana:var: bookmarks_enabledfoo = str
# ana:var: filesystem_enabledfoo = str
# ana:var: lua_factory_enabledfoo = str
# ana:var: youtube_enabledfoo = str

supported_arch = {
    'x86' : 'x86',
    'x86_64' : 'x86'
}
arch = host_machine.cpu()
xyz = 'arch' / supported_arch[arch] #join_paths('arch', supported_arch[arch])
set_variable(xyz, true)
set_variable('arch1' / supported_arch[arch], true)
# ana:var: arch1/x86 = bool

set_variable(join_paths('a', 'b'), 1)
# ana:var: a/b = int
xyz = join_paths('a1', 'b')
set_variable(xyz, 1)
# ana:var: a1/b = int
supported_arch1 = {
    'x86' : 'x861',
    'x86_64' : 'x861'
}
arch1 = host_machine.cpu()
set_variable(join_paths('arch', supported_arch1[arch1]), true)
# ana:var: arch/x861 = bool
