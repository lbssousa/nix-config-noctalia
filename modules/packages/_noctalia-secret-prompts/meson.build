project('noctalia-secret-prompts', 'cpp',
  version: '1.0.0',
  license: 'MIT',
  default_options: ['cpp_std=c++23', 'warning_level=3', 'b_ndebug=false'],
)

add_project_arguments('-DSECRET_PROMPTS_VERSION="@0@"'.format(meson.project_version()), language: 'cpp')

core = static_library('secret_prompts_core',
  sources: files('src/assuan_session.cpp', 'src/askpass_plan.cpp', 'src/prompt_bridge.cpp'),
  include_directories: include_directories('src'),
)

executable('noctalia-pinentry',
  sources: files('src/pinentry_main.cpp'),
  include_directories: include_directories('src'),
  link_with: core,
  install: true,
)

executable('noctalia-askpass',
  sources: files('src/askpass_main.cpp'),
  include_directories: include_directories('src'),
  link_with: core,
  install: true,
)

test_inc = include_directories('src', 'tests')
foreach name : ['assuan_session', 'askpass_plan', 'prompt_bridge']
  test(name, executable(name + '_test',
    sources: files('tests/' + name + '_test.cpp'),
    include_directories: test_inc,
    link_with: core,
  ))
endforeach
