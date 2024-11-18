import React from 'react';
import { Layout } from 'antd';
const { Footer, Sider } = Layout;

import SelaLogo from './SelaLogo';
import AppMenu from './AppMenu';
import Spacing from './Spacing';

const Nav = ({ menuItems, onMenuClick }) => {
  return (
    <Sider
      breakpoint="lg"
      collapsedWidth="0"
      width={350}
      style={{ position: 'fixed', height: '100%', left: 0 }}
    >
      <SelaLogo />

      <Spacing margin="64px" />

      {menuItems.map((item, index) => (
        <div key={index} onClick={() => onMenuClick(item)}>
          <AppMenu leftIcon={item.leftIcon} text={item.text} />
        </div>
      ))}
    </Sider>
  );
};

export default Nav;
