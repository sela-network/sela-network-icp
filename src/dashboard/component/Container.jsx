import React from 'react';

import Color from '../style/Color';

const Container = ({ background = Color.semiGray, children }) => {
  return (
    <div
      style={{
        background: background,
        padding: 24,
        borderRadius: 30,
        display: 'flex',
        flexDirection: 'column',
      }}
    >
      {children}
    </div>
  );
};

export default Container;
