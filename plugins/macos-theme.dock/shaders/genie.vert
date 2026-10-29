#version 440
// The macOS genie: the window pours through a curved funnel into its dock
// icon. progress runs 0 (the window) to 1 (inside the icon); restoring plays
// it backwards. Rects are x, y, w, h in the overlay's coordinates. Compile: qsb --qt6 -o genie.vert.qsb genie.vert

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    vec4 win;
    vec4 icon;
};

out gl_PerVertex { vec4 gl_Position; };

float ease(float t) { return t * t * (3.0 - 2.0 * t); }

void main() {
    vec2 uv = qt_MultiTexCoord0;
    float winBottom = win.y + win.w;
    float iconBottom = icon.y + icon.w;

    // A funnel from the window's top corners down to the icon's edges, its
    // sides S-curves. The window pours through it: first its bottom edge runs
    // down into the icon, stretching the window along the funnel, then its
    // top follows.
    float bottom = mix(winBottom, iconBottom, ease(clamp(progress / 0.45, 0.0, 1.0)));
    float top = mix(win.y, icon.y, ease(clamp((progress - 0.3) / 0.7, 0.0, 1.0)));
    float y = mix(top, bottom, uv.y);

    float along = ease(clamp((y - win.y) / max(1.0, icon.y - win.y), 0.0, 1.0));
    float left = mix(win.x, icon.x, along);
    float right = mix(win.x + win.z, icon.x + icon.z, along);

    qt_TexCoord0 = uv;
    gl_Position = qt_Matrix * vec4(mix(left, right, uv.x), y, 0.0, 1.0);
}
