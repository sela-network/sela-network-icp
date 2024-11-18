import React from 'react';
import sela from '../assets/icons/ic_sela.svg';
import history from '../assets/icons/ic_history.svg';
import gift from '../assets/icons/ic_gift.svg';
import arrowRight from '../assets/icons/ic_arrow_right.svg';

const iconMap = {
  sela,
  history,
  gift,
  arrowRight,
};

const Icon = ({ name, style, backgroundColor = '#1D1D1D', ...props }) => {
  const selectedIcon = iconMap[name];

  if (!selectedIcon) return null;

  // Define default styles
  const defaultStyle = {
    width: '24px',
    height: '24px',
    color: '#fff',
    fill: 'currentColor', // Allows color customization via CSS or style
    ...style, // Override default styles with passed-in `style` prop
  };

  return (
    <div
      style={{
        padding: 12,
        background: backgroundColor,
        borderRadius: 100,
        display: 'flex',
        justifyContent: 'center',
        alignItems: 'center',
      }}
    >
      <img src={selectedIcon} style={defaultStyle} {...props} />
    </div>
  );
};

export default Icon;
