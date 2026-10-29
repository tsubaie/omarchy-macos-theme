#version 440
// Draws the captured window as the genie bends it, fading a little at the end.
// Compile: qsb --qt6 -o genie.frag.qsb genie.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    vec4 win;
    vec4 icon;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    float fade = 1.0 - smoothstep(0.85, 1.0, progress);
    fragColor = texture(source, qt_TexCoord0) * qt_Opacity * fade;
}
