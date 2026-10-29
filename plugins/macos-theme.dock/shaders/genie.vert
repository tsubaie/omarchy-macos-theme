#version 440
// The macOS genie: the window's bottom pinches toward its dock icon, then the
// whole window pours into it, lower rows first. progress runs 0 (the window)
// to 1 (inside the icon); restoring plays it backwards. Rects are x, y, w, h
// in the overlay's coordinates. Compile: qsb --qt6 -o genie.vert.qsb genie.vert

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
    // Pinch first, then slide; the two overlap for a continuous pour.
    float pinch = ease(clamp(progress / 0.5, 0.0, 1.0));
    float slide = clamp((progress - 0.25) / 0.75, 0.0, 1.0);

    // Each row slides from its place in the window to its place in the icon;
    // the bottom row leaves at once, the top one last.
    float row = ease(clamp(slide * 1.7 - (1.0 - uv.y) * 0.7, 0.0, 1.0));
    float y = mix(win.y + uv.y * win.w, icon.y + uv.y * icon.w, row);

    // Rows narrow toward the icon's width the closer they are to the dock,
    // which bends the sides into the genie's curve.
    float reach = clamp((y - win.y) / max(1.0, icon.y + icon.w - win.y), 0.0, 1.0);
    float squeeze = mix(ease(reach) * pinch, 1.0, row);
    float left = mix(win.x, icon.x, squeeze);
    float right = mix(win.x + win.z, icon.x + icon.z, squeeze);

    qt_TexCoord0 = uv;
    gl_Position = qt_Matrix * vec4(mix(left, right, uv.x), y, 0.0, 1.0);
}
