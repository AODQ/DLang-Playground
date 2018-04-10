import std.stdio, std.file, std.string,  std.range, std.array, std.exception;
import std.random, std.math;
import imageformats;
import gl3n.linalg;
import std.algorithm;
static import render;
import derelict.opengl, derelict.glfw3;
import std.mathspecial;

immutable size_t Amt = 1024;

alias float2 = vec2;
alias float3 = vec3;
alias float4 = vec4;

struct Data {
  float3[] o;
  float4[] c;
}

T Clamp(T) ( T a, T l, T u ) {
  if ( a < l ) return l;
  if ( a > u ) return u;
  return a;
}

uint discardcount = 0;

// Gaussian distribution
float Uniform ( ) {
  return (normalDistribution(uniform(-1.0f, 1.0f))-0.5f)*2.0f;
}

void Discard ( ref Data data ) {
  foreach ( i; 0 .. 3 ) {
    int idx = cast(int)uniform(0, Amt);
    // completely randomize one
    data.o[idx] = float3(uniform(-1.0f,1.0f),uniform(-1.0f,1.0f),
                         uniform(0.01f,0.3f));
    data.c[idx] = float4(uniform(0.0f, 1.0f), uniform(0.0f, 1.0f),
                        uniform(0.0f, 1.0f), uniform(0.1f, 1.0f));
  }
}

void Randomize ( ref Data data, float score ) {
  // discard
  if ( discardcount > 5 && uniform(0.0f, 1.0f) > 0.5f ) {
    Discard(data);
    return;
  }
  int amt = 20;
  if ( discardcount > 1  ) amt = 10;
  if ( discardcount > 5  ) amt = 5;
  if ( discardcount > 10 ) amt = 1;
  // select random circle & randomize a bit of it
  foreach ( i; 0 .. uniform(1, 1+amt) ) {
    int idx = cast(int)uniform(0, Amt);
    foreach ( ref v; data.o[idx].vector[0..3] ) {
      v = Clamp(v + Uniform()*0.51f, -1.0f, 1.0f);
    }
    data.o[idx].z = Clamp(data.o[idx].z+Uniform()*0.11f, 0.015f, 0.300f);
    foreach ( ref c; data.c[idx].vector )
      c = Clamp(c + Uniform()*0.51f, 0.0f, 1.0f);
    data.c[idx].w = Clamp(data.c[idx].w, 0.2f, 1.0f);
  }
}

void Generate_Points (ref Data data) {
  data.o.length = data.c.length = Amt;
  foreach ( ref p; data.o ) {
    p.x = uniform(-1.0f, 1.0f);
    p.y = uniform(-1.0f, 1.0f);
    p.z = uniform( 0.0f, 1.0f);
  }
  foreach ( ref p; data.c ) {
    p.x = uniform( 0.0f, 1.0f);
    p.y = uniform( 0.0f, 1.0f);
    p.z = uniform( 0.0f, 1.0f);
    p.w = uniform( 0.0f, 1.0f);
  }
}

auto sqr(T)(T x){return x*x;}

float3 To_Float3 ( ubyte[] a ) {
  return float3(a[0], a[1], a[2])/256.0f;
}

float Compute_Difference(ubyte[] img, ubyte[] oimg) {
  float diff = 0.0f;
  foreach ( j; 0 .. render.window_height ) {
    foreach ( i; 0 .. render.window_width ) {
      auto idx = j*render.window_width*4 + i*4;
      float3 o = To_Float3(oimg[idx+0..idx+3]),
             n = To_Float3( img[idx+0..idx+3]);
      diff += sqr(distance(n, o));
    }
  }
  return diff;
}

void main(string[] args) {
  enforce(args.length == 2, "Pass in a file");
  // pregen data data
  Data data, gendata;
  data.Generate_Points;
  gendata.Generate_Points;
  // get image
  auto fimg = read_image(args[1]);
  ubyte[] img = fimg.pixels.dup;
  ubyte[] oimg = img.dup;
  // init opengl
  Initialize(fimg.w, fimg.h);
  glEnable(GL_DEBUG_OUTPUT);
  glDebugMessageCallback(cast(GLDEBUGPROC)&Message_Callback, null);

  glGenTextures(1, &imgtex);
  glBindTexture(GL_TEXTURE_2D, imgtex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, fimg.w, fimg.h,
               0, GL_RGBA, GL_UNSIGNED_BYTE, fimg.pixels.ptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

  float diff = float.max;
  // algorithm
  float score = 100.0f;
  while ( true ) {
    auto time = glfwGetTime();
    // render anew
    discardcount += 1;
    foreach ( i; 0 .. gendata.o.length ) {
      gendata.o[i] = data.o[i];
      gendata.c[i] = data.c[i];
    }
    gendata.Randomize(score);
    gendata.Render;
    // calculate diff
    glReadPixels(0, 0, render.window_width, render.window_height, GL_RGBA,
                 GL_UNSIGNED_BYTE, oimg.ptr);
    float ndif = Compute_Difference(img, oimg);
    if ( ndif < diff ) {
      discardcount = 0;
      // postblit not working..?
      // data = gendata;
      foreach ( i; 0 .. gendata.o.length ) {
        data.o[i] = gendata.o[i];
        data.c[i] = gendata.c[i];
      }
      diff = ndif;
      data.Render_Screen();
    }
    score = ndif;
    // render screen
    static bool gtim = true;
    if ( fmod(glfwGetTime(), 2.2f) <= 0.51f ) {
      if ( gtim ) {
        writeln((glfwGetTime()-time)*1000.0f);
        data.Render_Screen();
      }
      gtim = false;
    } else gtim = true;
    if ( render.Event_Poll() ) break;
  }
}

GLuint vao, vbot, vboo, vboc, program_id, fbop_id, fvao;
GLuint framebuffer, framebuffer_tex;
GLuint imgtex;

void Initialize ( int ww, int wh ) {
  render.Initialize(ww, wh);
  fbop_id = render.Load_Shaders(q{#version 330 core
    layout(location = 0) in vec3 vpos;
    out vec2 fcoord;
    void main ( ) {gl_Position = vec4(vpos, 1); fcoord = (vpos.xy+1.0f)/2.0f;}
  }, q{#version 330 core
    #extension GL_ARB_explicit_uniform_location : enable
    in vec2 fcoord; out vec4 out_colour;
    layout(location = 0) uniform sampler2D ga_img;
    layout(location = 1) uniform sampler2D ac_img;
    void main ( ) {
      vec2 C = fcoord*vec2(1.0f, -1.0f);
      out_colour = texture(ga_img, C);
      // out_colour = mix(texture(ga_img, C), texture(ac_img, C), 0.00);
    }
  });
  program_id = render.Load_Shaders(q{#version 330 core
    #define float4 vec4
    #define float3 vec3
    #define float2 vec2
    layout(location = 0) in float3 vertex_pos;
    layout(location = 1) in float3 circle_o;
    layout(location = 2) in float4 circle_c;

    out float3 frag_coord;
    out float4 frag_col;
    void main ( ) {
      gl_Position = float4((vertex_pos*circle_o.z)+float3(circle_o.xy, 1), 1);
      frag_coord = float3(vertex_pos.xy, circle_o.z);
      frag_col = circle_c;
    }
  }, q{#version 330 core
    #extension GL_ARB_explicit_uniform_location : enable
    #define float4 vec4
    #define float3 vec3
    #define float2 vec2
    in float3 frag_coord;
    in float4 frag_col;
    out float4 out_colour;

    void main ( ) {
      if ( length(frag_coord.xy) - 1.0f > 0.0f ) discard;
      out_colour = frag_col*float4(float3(1.0f), 1.0f-length(frag_coord.xy));
    }
  });
  float[] vertices = [
    -1.0f, -1.0f, 0.0f, 1.0f,  -1.0f, 0.0f, -1.0f, 1.0f,  0.0f,
    1.0f,  1.0f,  0.0f, -1.0f, 1.0f,  0.0f, 1.0f,  -1.0f, 0.0f,
  ];
  glGenFramebuffers(1, &framebuffer);
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
  glGenTextures(1, &framebuffer_tex);
  glBindTexture(GL_TEXTURE_2D, framebuffer_tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, render.window_width,
               render.window_height, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                         framebuffer, 0);
  glGenVertexArrays(1, &vao);
  glBindVertexArray(vao);
  glGenBuffers(1, &vbot);
  glBindBuffer(GL_ARRAY_BUFFER, vbot);
  glBufferData(GL_ARRAY_BUFFER, GLfloat.sizeof*vertices.length, vertices.ptr,
               GL_STATIC_DRAW);
  glGenBuffers(1, &vboc);
  glBindBuffer(GL_ARRAY_BUFFER, vboc);
  glBufferData(GL_ARRAY_BUFFER, GLfloat.sizeof*4*Amt, null, GL_STREAM_DRAW);
  glGenBuffers(1, &vboo);
  glBindBuffer(GL_ARRAY_BUFFER, vboo);
  glBufferData(GL_ARRAY_BUFFER, GLfloat.sizeof*3*Amt, null, GL_STREAM_DRAW);
  glGenVertexArrays(1, &fvao);
}

void Render ( ref Data data ) {
  // prepare buffres
  float[] obuff, cbuff;
  obuff.length = Amt*3;
  cbuff.length = Amt*4;
  foreach ( i; 0 .. data.o.length ) {
    obuff[i*3+0..i*3+3] = data.o[i].vector;
  }
  foreach ( i; 0 .. data.c.length ) {
    cbuff[i*4+0..i*4+4] = data.c[i].vector;
  }
  glBindBuffer(GL_ARRAY_BUFFER, vboc);
  glBufferData(GL_ARRAY_BUFFER, GLfloat.sizeof*4*Amt, cbuff.ptr,
               GL_STREAM_DRAW);
  glBindBuffer(GL_ARRAY_BUFFER, vboo);
  glBufferData(GL_ARRAY_BUFFER, GLfloat.sizeof*3*Amt, obuff.ptr,
               GL_STREAM_DRAW);
  // render to framebuffer
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glUseProgram(program_id);
  glBindVertexArray(vao);
  glEnableVertexAttribArray(0);
  glBindBuffer(GL_ARRAY_BUFFER, vbot);
  glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 0, null);
  glEnableVertexAttribArray(1);
  glBindBuffer(GL_ARRAY_BUFFER, vboo);
  glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 0, null);
  glEnableVertexAttribArray(2);
  glBindBuffer(GL_ARRAY_BUFFER, vboc);
  glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, 0, null);

  glVertexAttribDivisor(0, 0);
  glVertexAttribDivisor(1, 1);
  glVertexAttribDivisor(2, 1);
  glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, Amt);
}

void Render_Screen ( ref Data data ) {
  render.Begin_Frame();
  data.Render();
  // render screen
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glUseProgram(fbop_id);
  glBindVertexArray(fvao);
  glEnableVertexAttribArray(0);
  glBindBuffer(GL_ARRAY_BUFFER, vbot);
  glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 0, null);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, framebuffer_tex);
  glUniform1i(0, 0);
  glActiveTexture(GL_TEXTURE1);
  glBindTexture(GL_TEXTURE_2D, imgtex);
  glUniform1i(1, 1);
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 6);
  render.End_Frame();
}

extern(C) void Message_Callback( GLenum source,
                      GLenum type,
                      GLuint id,
                      GLenum severity,
                      GLsizei length,
                      const GLchar* message,
                      const void* userParam ) nothrow @nogc
{
  // from khronos.org/opengl/wiki/opengl_error
  printf("%s\n", message);
  assert(false);
}
