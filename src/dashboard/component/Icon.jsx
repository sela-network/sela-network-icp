import React from 'react';

import IconArrowRight from './Icons/IconArrowRight';
import IconGift from './Icons/IconGift';
import IconHistory from './Icons/IconHistory';
import IconSela from './Icons/IconSela';

import Color from '../style/Color';

const iconMap = {
  sela: IconSela,
  history: IconHistory,
  gift: IconGift,
  arrowRight: IconArrowRight,
};

const Icon = ({ name, style, backgroundColor = Color.semiGray, ...props }) => {
  const SelectedIcon = iconMap[name];

  if (!SelectedIcon) return null;

  // Define default styles
  const defaultStyle = {
    width: '24px',
    height: '24px',
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
      <SelectedIcon style={defaultStyle} {...props} />
    </div>
  );
};

export default Icon;
