module render;
import derelict.opengl;
import derelict.glfw3;
import std.stdio, std.string;

GLFWwindow* window;
int window_width, window_height;
// int window_width = 640, window_height = 640;
// int window_width = 1440, window_height = 1080;

void Initialize ( int ww, int wh ) {
  window_width = ww; window_height = wh;
  DerelictGL3.load();
  DerelictGLFW3.load();
  glfwInit();

  glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
  glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
  glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE );
  glfwWindowHint(GLFW_RESIZABLE,      GL_FALSE                 );
  glfwWindowHint(GLFW_FLOATING,       GL_TRUE                  );
  glfwWindowHint(GLFW_REFRESH_RATE,  0                         );
  glfwSwapInterval(0);

  window = glfwCreateWindow(window_width, window_height, "GA test", null, null);
  glfwSwapInterval(0);

  glfwWindowHint(GLFW_FLOATING, GL_TRUE);
  glfwMakeContextCurrent(window);
  DerelictGL3.reload();
  glClampColor(GL_CLAMP_READ_COLOR, GL_FALSE);
  glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS_ARB);

  glClearColor(0.02f, 0.02f, 0.02f, 1.0f);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glDisable(GL_DEPTH_TEST);
  glfwSwapInterval(0);
}
void Begin_Frame ( ) {
  glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
}
void End_Frame ( ) {
  glfwSwapBuffers(window);
}
bool Event_Poll ( ) {
  glfwPollEvents();
  return ( glfwWindowShouldClose(window) ||
           glfwGetKey(window, GLFW_KEY_Q) == GLFW_PRESS ||
           glfwGetKey(window, GLFW_KEY_ESCAPE) == GLFW_PRESS );
}

GLuint Load_Shaders(string vertex, string fragment) {
  GLuint vshader = glCreateShader(GL_VERTEX_SHADER),
         fshader = glCreateShader(GL_FRAGMENT_SHADER);

  void Check ( string shstr, GLuint sh ) {
    GLint res;
    int info_log_length;
    glGetShaderiv(sh, GL_COMPILE_STATUS, &res);
    glGetShaderiv(sh, GL_INFO_LOG_LENGTH, &info_log_length);
    if ( info_log_length > 0 ){
      char[] msg; msg.length = info_log_length+1;
      glGetShaderInfoLog(sh, info_log_length, null, msg.ptr);
      writeln(shstr, ": ", msg);
      assert(false);
    }
  }

  immutable(char)* vertex_c   = toStringz(vertex),
                   fragment_c = toStringz(fragment);
  glShaderSource(vshader, 1, &vertex_c, null);
  glCompileShader(vshader);
  Check("vertex", vshader);

  glShaderSource(fshader, 1, &fragment_c, null);
  glCompileShader(fshader);
  Check("fragment", fshader);

  GLuint program_id = glCreateProgram();
  glAttachShader(program_id, vshader);
  glAttachShader(program_id, fshader);
  glLinkProgram(program_id);
  glDetachShader(program_id, vshader);
  glDetachShader(program_id, fshader);
  glDeleteShader(vshader);
  glDeleteShader(fshader);
  return program_id;
}
