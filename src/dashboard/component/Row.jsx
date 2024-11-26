import React from 'react';

const Row = ({ children, justifyContent = 'flex-start' }) => {
  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'row',
        flexWrap: 'wrap',
        justifyContent: justifyContent,
        gap: 16,
      }}
    >
      {children}
    </div>
  );
};

export default Row;
