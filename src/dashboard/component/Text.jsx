import React from 'react';

const Text = ({
  size = '16px', // Default size is 16px
  color = '#fff', // Default color is white
  weight = 'normal', // Default weight is normal
  decoration = 'none', // Default decoration is none
  children, // The text to display
  style = {}, // Additional custom styles
}) => {
  const fontWeightMap = {
    normal: 'normal',
    bold: 'bold',
    light: '300',
    semiBold: '600',
  };

  return (
    <span
      style={{
        fontSize: size,
        color: color,
        fontFamily: 'Urbanist',
        fontWeight: fontWeightMap[weight] || 'normal', // Use the weight map
        textDecoration: decoration,
        ...style, // Allow overriding styles
      }}
    >
      {children}
    </span>
  );
};

export default Text;