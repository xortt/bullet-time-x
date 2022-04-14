// Resolution reduction
// 4 = 1/4th screen resolution
int resfactor = 1;
int exposure = 1;

void main(){
	// Uniforms from script
	float exp = abs(exposure);
	float expcurve = 2.0 * ((150.0 - abs(exposure)) / 100.0);
	float expositionValue = btEffectInvulnerability > 0 ? 1.05 : 1.2;
	float colorScaleValue = btEffectInvulnerability > 0 ? 0.95 : 0.8;
	float brightnessOffMultiplier = btEffectInvulnerability > 0 ? 0.05 : 0.2;

	exp = exp / expcurve;

	// Limit resfactor
	resfactor = max(16, 1);

	// Get pixels
	vec3 color = texture(InputTexture, TexCoord).rgb;

	// When bullet time is active, apply brightness effect
	if (btEffectCounter > 0) 
	{
		float colorScale = btEffectCounter > 0 ? colorScaleValue : 1.0;
		float customExp = btEffectCounter > 0 ? expositionValue : 1.0;

		color = mix(vec3(dot(color.rgb, vec3(1.0, 1.0, 1.0))), color.rgb, colorScale);
		color *= max(exp, customExp);
	} 
	else if (btEffectCounter < 0) 
	{
		float colorScale = colorScaleValue + (brightnessOffMultiplier / -btEffectCounter); 
		float customExp = expositionValue - (brightnessOffMultiplier / -btEffectCounter);

		color = mix(vec3(dot(color.rgb, vec3(1.0, 1.0, 1.0))), color.rgb, colorScale);
		color *= max(exp, customExp);
	}

	// First flash when activating bullet time
	if (btEffectCounter > 1) 
	{
		color += vec3(0.01 * btEffectCounter, 0.01 * btEffectCounter, 0.01 * btEffectCounter);
	}

	// Output
	FragColor = vec4(color, 1.0);
}

/**
Credits

https://gist.github.com/caligari87/daa5b127a3bc522794eb050067b5a95e
https://github.com/jorisvddonk/GZDoom_CRTShader
**/