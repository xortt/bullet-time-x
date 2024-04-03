void main()
{
    vec3 C = vec3( 0. );
    int delay = 5; // Define delay here. Adjust this value to get the desired effect.
    float feedbackAmount = 0.66; // Define feedbackAmount here. Adjust this value to get the desired effect.

    // Calculate the distance from the current pixel to the center of the screen
    float distance = length(TexCoord - vec2(0.5));

    // Create a mask that smoothly transitions from 0.0 in the center of the screen to 1.0 elsewhere
    float mask = smoothstep(0.0, 0.38, distance); // Adjust the range as needed

    vec3 original = texture( InputTexture, TexCoord ).rgb;


    for( int i = 0; i < samples; i++ )
    {
        vec3 current = texture( InputTexture, TexCoord + steps * i ).rgb;
        vec3 delayed = texture( InputTexture, TexCoord + steps * (i + delay) ).rgb; // Calculate delayed color here
        C += mix(current, delayed, feedbackAmount) * increment;
    }

    // Mix the original color and the processed color based on the mask
    C = mix(original, C, mask);
    
    FragColor = vec4( C, 1. );
}

// Credits: based on MBlur by Pixel Eater (https://forum.zdoom.org/viewtopic.php?t=62772) + Some help from copilot :P