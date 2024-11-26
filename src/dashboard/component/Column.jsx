import React from 'react';

const Column = ({ children, justifyContent = 'space-between' }) => {
  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        justifyContent: justifyContent,
        gap: 16,
      }}
    >
      {children}
    </div>
  );
};

export default Column;
