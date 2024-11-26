import React from 'react';

import Color from '../style/Color';

const Container = ({
  background = Color.semiGray,
  children,
  alignItems = 'normal',
  style,
}) => {
  return (
    <div
      style={{
        background: background,
        padding: 24,
        borderRadius: 30,
        display: 'flex',
        flexDirection: 'column',
        alignItems: alignItems,
        gap: 16,
        ...style,
      }}
    >
      {children}
    </div>
  );
};

export default Container;
